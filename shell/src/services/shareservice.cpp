#include "shareservice.h"
#include "../ipc/callerpid.h"

#include "dbusnormalize.h"
#include "marathon-shell-native/src/apps.cxxqt.h"

#include <QClipboard>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QTimer>
#include <QUrl>

#include <algorithm>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
    constexpr int kMaxResources = 32;
    constexpr int kMaxText      = 64 * 1024;
    constexpr int kTries        = 50;
} // namespace

ShareService::ShareService(Apps *apps, QStringList sharedFolders,
                           AppForPid appForPid, Raise raise, QObject *parent)
    : QObject(parent)
    , m_apps(apps)
    , m_sharedFolders(std::move(sharedFolders))
    , m_appForPid(std::move(appForPid))
    , m_raise(std::move(raise)) {}

bool ShareService::registerOnSessionBus() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    return bus.registerObject(QStringLiteral("/"), this, QDBusConnection::ExportScriptableSlots) &&
        bus.registerService(QStringLiteral("org.sailfishos.share"));
}

bool ShareService::mimeMatches(const QString &accepted, const QString &mimeType) {
    if (accepted == mimeType || accepted == QLatin1String("*/*"))
        return true;
    if (accepted.endsWith(QLatin1String("/*")) && mimeType.startsWith(accepted.chopped(1)))
        return true;
    return mimeType.endsWith(QLatin1String("/*")) && accepted.startsWith(mimeType.chopped(1));
}

int ShareService::openShared(qint64 pid, const QString &path, const QStringList &sharedFolders,
                             QString *hostPath) {
    const QString clean = QDir::cleanPath(path);
    if (pid <= 0 || !QDir::isAbsolutePath(clean))
        return -1;
    const QString canonical = QFileInfo(clean).canonicalFilePath();
    bool          seen = false, onHost = false;
    for (const QString &folder : sharedFolders) {
        const QString root = QFileInfo(folder).canonicalFilePath();
        seen |= clean.startsWith(QDir::cleanPath(folder) + QLatin1Char('/'));
        onHost |= !root.isEmpty() && canonical.startsWith(root + QLatin1Char('/'));
    }
    if (!seen || !onHost)
        return -1;
    const QByteArray inProcess = QStringLiteral("/proc/%1/root%2").arg(pid).arg(clean).toLocal8Bit();
    const int        fd        = ::open(inProcess.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0)
        return -1;
    struct stat theirs{};
    struct stat ours{};
    if (::fstat(fd, &theirs) != 0 || ::stat(canonical.toLocal8Bit().constData(), &ours) != 0 ||
        !S_ISREG(theirs.st_mode) || theirs.st_dev != ours.st_dev || theirs.st_ino != ours.st_ino) {
        ::close(fd);
        return -1;
    }
    *hostPath = canonical;
    return fd;
}

void ShareService::share(const QVariantMap &configuration) {
    const QVariantMap config = normalizeMapDeep(configuration);
    const QVariant    raw    = config.value(QStringLiteral("resources"));
    const QVariantList resources =
        raw.typeId() == QMetaType::QVariantList ? raw.toList() : QVariantList{raw};
    const QString mimeType = config.value(QStringLiteral("mimeType")).toString().left(128);
    const QString title    = config.value(QStringLiteral("title")).toString().left(256);
    const auto    refuse   = [this](QDBusError::ErrorType type, const QString &why) {
        if (calledFromDBus())
            sendErrorReply(type, why);
    };
    if (resources.isEmpty() || resources.size() > kMaxResources) {
        refuse(QDBusError::InvalidArgs, QStringLiteral("1 to 32 resources"));
        return;
    }

    qint64  pid  = -1;
    QString from;
    if (calledFromDBus()) {
        pid  = callerPid(connection(), message().service());
        from = m_appForPid ? m_appForPid(pid) : QString();
    }
    // A session service (deckardd) may name the app that shares; an app may
    // not name another.
    const bool    fromApp = !from.isEmpty() && !from.startsWith(QLatin1String("service:"));
    const QString source  = fromApp ? QString() : config.value(QStringLiteral("source")).toString().left(256);

    QList<Item> items;
    for (const QVariant &resource : resources) {
        Item item;
        if (resource.typeId() == QMetaType::QString) {
            QString hostPath;
            const int fd = from.isEmpty() ? -1 :
                                            openShared(pid, resource.toString(), m_sharedFolders,
                                                       &hostPath);
            if (fd < 0) {
                refuse(QDBusError::AccessDenied, QStringLiteral("Not a shared file"));
                return;
            }
            item.file = QDBusUnixFileDescriptor(fd);
            ::close(fd);
            item.hostPath = hostPath;
            item.name     = QFileInfo(hostPath).fileName();
            item.mimeType = QMimeDatabase().mimeTypeForFile(hostPath).name();
        } else if (const QVariantMap map = resource.toMap();
                   map.value(QStringLiteral("fileDescriptor")).userType() ==
                   qMetaTypeId<QDBusUnixFileDescriptor>()) {
            // A descriptor is its own proof of access, whoever sends it.
            const auto  fd = map.value(QStringLiteral("fileDescriptor")).value<QDBusUnixFileDescriptor>();
            struct stat st{};
            if (!fd.isValid() || ::fstat(fd.fileDescriptor(), &st) != 0 || !S_ISREG(st.st_mode)) {
                refuse(QDBusError::InvalidArgs, QStringLiteral("Not a regular file"));
                return;
            }
            item.file = fd;
            item.name = QFileInfo(map.value(QStringLiteral("name")).toString()).fileName().left(256);
            if (item.name.isEmpty() || item.name == QLatin1String(".."))
                item.name = QStringLiteral("file");
            item.mimeType =
                QMimeDatabase().mimeTypeForFile(item.name, QMimeDatabase::MatchExtension).name();
        } else {
            item.text             = map.value(map.contains(QStringLiteral("data")) ?
                                                  QStringLiteral("data") :
                                                  QStringLiteral("status"))
                            .toString();
            item.name = map.value(QStringLiteral("name"), map.value(QStringLiteral("linkTitle")))
                            .toString()
                            .left(256);
            if (item.text.isEmpty() || item.text.size() > kMaxText) {
                refuse(QDBusError::InvalidArgs, QStringLiteral("Text of 1 to 65536 characters"));
                return;
            }
        }
        items << item;
    }

    const auto isFile   = [](const Item &i) { return i.file.isValid(); };
    const int  files    = int(std::count_if(items.cbegin(), items.cend(), isFile));
    const bool textOnly = files == 0;
    QString    type     = mimeType;
    if (type.isEmpty())
        type = textOnly ? QStringLiteral("text/plain") :
                          std::find_if(items.cbegin(), items.cend(), isFile)->mimeType;

    m_title    = title;
    m_mimeType = type;
    m_items    = items;
    QVariantMap request{{QStringLiteral("title"), title},
                        {QStringLiteral("mimeType"), type},
                        {QStringLiteral("count"), items.size()},
                        {QStringLiteral("targets"), targetsFor(type, {from, source}, textOnly)}};
    for (const Item &item : std::as_const(items)) {
        if (!item.text.isEmpty() && !request.contains(QStringLiteral("text")))
            request.insert(QStringLiteral("text"), item.text.left(500));
        if (item.file.isValid() && !request.contains(QStringLiteral("image")) &&
            item.mimeType.startsWith(QLatin1String("image/")))
            request.insert(QStringLiteral("image"),
                           item.hostPath.isEmpty() ?
                               QStringLiteral("file:///proc/self/fd/%1").arg(item.file.fileDescriptor()) :
                               QUrl::fromLocalFile(item.hostPath).toString());
    }
    ++m_request;
    emit requested(request);
    askAndroid(textOnly ? QStringLiteral("text/plain") : type, source, files);
}

// deckardd lists the Android activities that take the type; they join the
// sheet when it answers, leaving out the sharing app and, for several
// files, those that take only one.
void ShareService::askAndroid(const QString &mimeType, const QString &source, int files) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.interface()->isServiceRegistered(QStringLiteral("org.marathonos.Deckard")).value())
        return;
    QDBusMessage call = QDBusMessage::createMethodCall(
        QStringLiteral("org.marathonos.Deckard"), QStringLiteral("/org/marathonos/Deckard"),
        QStringLiteral("org.marathonos.Deckard1.Share"), QStringLiteral("ShareTargets"));
    call << mimeType;
    const int  request  = m_request;
    const auto skipped  = source.startsWith(QLatin1String("waydroid.")) ? source.mid(9) : QString();
    auto      *watcher  = new QDBusPendingCallWatcher(bus.asyncCall(call, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, request, skipped, files](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (w->isError() || request != m_request)
                    return;
                const QVariant arg = w->reply().arguments().value(0);
                const QList<QVariantMap> found =
                    arg.canConvert<QDBusArgument>() ? qdbus_cast<QList<QVariantMap>>(arg.value<QDBusArgument>()) :
                                                      QList<QVariantMap>();
                QVariantList added;
                for (const QVariantMap &target : found) {
                    const QString activity = target.value(QStringLiteral("id")).toString();
                    if (activity.isEmpty() || activity.size() > 256 ||
                        target.value(QStringLiteral("pkg")).toString() == skipped ||
                        (files > 1 && !target.value(QStringLiteral("multiple")).toBool()))
                        continue;
                    const QString id = QStringLiteral("android:") + activity;
                    m_targets << Target{id, QString(), activity, true};
                    added << QVariantMap{{QStringLiteral("id"), id},
                                         {QStringLiteral("name"), target.value(QStringLiteral("label")).toString().left(64)},
                                         {QStringLiteral("icon"), target.value(QStringLiteral("icon")).toString()}};
                }
                if (!added.isEmpty())
                    emit targetsAdded(added);
            });
}

QVariantList ShareService::targetsFor(const QString &mimeType, const QStringList &leftOut,
                                      bool textOnly) {
    m_targets.clear();
    QVariantList out;
    const QStringList ids = m_apps ? m_apps->getAllAppIds() : QStringList();
    for (const QString &appId : ids) {
        const QVariantMap info = m_apps->getApp(appId);
        if (info.isEmpty() || leftOut.contains(appId))
            continue;
        QFile manifest(info.value(QStringLiteral("absolutePath")).toString() + QStringLiteral("/manifest.json"));
        if (!manifest.open(QIODevice::ReadOnly))
            continue;
        const QJsonArray methods = QJsonDocument::fromJson(manifest.readAll())
                                       .object()
                                       .value(QStringLiteral("shareMethods"))
                                       .toArray();
        for (const auto &value : methods) {
            const QJsonObject method   = value.toObject();
            const QJsonArray  accepted = method.value(QStringLiteral("mimeTypes")).toArray();
            if (!std::any_of(accepted.begin(), accepted.end(), [&mimeType](const QJsonValue &a) {
                    return mimeMatches(a.toString(), mimeType);
                }))
                continue;
            const QString name = method.value(QStringLiteral("name")).toString();
            const QString id   = appId + QLatin1Char('/') + name;
            m_targets << Target{id, appId, name};
            out << QVariantMap{{QStringLiteral("id"), id},
                               {QStringLiteral("name"), info.value(QStringLiteral("name"))},
                               {QStringLiteral("action"), method.value(QStringLiteral("title")).toString()},
                               {QStringLiteral("icon"), info.value(QStringLiteral("icon"))}};
        }
    }
    if (textOnly) {
        m_targets << Target{QStringLiteral("clipboard"), QString(), QString()};
        out << QVariantMap{{QStringLiteral("id"), QStringLiteral("clipboard")},
                           {QStringLiteral("name"), tr("Copy")},
                           {QStringLiteral("glyph"), QStringLiteral("copy")}};
    }
    return out;
}

void ShareService::choose(const QString &targetId) {
    const auto it = std::find_if(m_targets.cbegin(), m_targets.cend(),
                                 [&targetId](const Target &t) { return t.id == targetId; });
    if (it == m_targets.cend())
        return;
    const Target target = m_targets.takeAt(std::distance(m_targets.cbegin(), it));
    m_targets.clear();

    if (target.id == QLatin1String("clipboard")) {
        QStringList texts;
        for (const Item &item : std::as_const(m_items))
            texts << item.text;
        QGuiApplication::clipboard()->setText(texts.join(QLatin1Char('\n')));
        m_items.clear();
        emit delivered(target.id);
        return;
    }

    QVariantList resources;
    for (const Item &item : std::as_const(m_items)) {
        if (!item.file.isValid())
            resources << QVariantMap{{QStringLiteral("name"), item.name},
                                     {QStringLiteral("data"), item.text}};
        else
            resources << QVariantMap{{QStringLiteral("name"), item.name},
                                     {QStringLiteral("fileDescriptor"), QVariant::fromValue(item.file)}};
    }
    m_items.clear();
    const QVariantMap configuration{{QStringLiteral("mimeType"), m_mimeType},
                                    {QStringLiteral("title"), m_title},
                                    {QStringLiteral("resources"), resources}};
    if (target.android) {
        shareToAndroid(target.id, target.method, configuration);
        return;
    }
    if (m_raise)
        m_raise(target.appId);
    deliver(target.id, target.appId, target.method, configuration, 0);
}

// deckardd brings the Android app's window forward itself (ExpectAppWindow,
// a call back into the shell while this one waits), so nothing here blocks.
void ShareService::shareToAndroid(const QString &targetId, const QString &activity,
                                  const QVariantMap &configuration) {
    QDBusMessage call = QDBusMessage::createMethodCall(
        QStringLiteral("org.marathonos.Deckard"), QStringLiteral("/org/marathonos/Deckard"),
        QStringLiteral("org.marathonos.Deckard1.Share"), QStringLiteral("Share"));
    call << activity << configuration;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, 20000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, targetId](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (w->isError())
            emit failed(targetId, w->error().message());
        else
            emit delivered(targetId);
    });
}

void ShareService::cancel() {
    m_items.clear();
    m_targets.clear();
}

// The app may still be starting: its name comes when its actions load, and
// its share object when its window's QML has.
void ShareService::deliver(const QString &targetId, const QString &appId, const QString &method,
                           const QVariantMap &configuration, int tries) {
    QDBusConnection bus     = QDBusConnection::sessionBus();
    const QString   service = QStringLiteral("org.marathonos.") + appId;
    const auto      retry   = [this, targetId, appId, method, configuration, tries]() {
        if (tries + 1 >= kTries) {
            emit failed(targetId, QStringLiteral("The app did not take the share"));
            return;
        }
        QTimer::singleShot(200, this, [this, targetId, appId, method, configuration, tries]() {
            deliver(targetId, appId, method, configuration, tries + 1);
        });
    };
    if (!bus.interface()->isServiceRegistered(service).value()) {
        retry();
        return;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(
        service, QStringLiteral("/share/") + method, QStringLiteral("org.sailfishos.share"),
        QStringLiteral("share"));
    call.setArguments({configuration});
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(call, 10000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, targetId, retry](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (!w->isError()) {
                    emit delivered(targetId);
                    return;
                }
                const QDBusError::ErrorType type = w->error().type();
                if (type == QDBusError::UnknownObject || type == QDBusError::UnknownMethod ||
                    type == QDBusError::ServiceUnknown)
                    retry();
                else
                    emit failed(targetId, w->error().message());
            });
}
