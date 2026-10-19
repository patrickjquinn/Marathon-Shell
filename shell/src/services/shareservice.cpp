#include "shareservice.h"

#include "dbusnormalize.h"
#include "marathonappregistry.h"

#include <QClipboard>
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

ShareService::ShareService(MarathonAppRegistry *apps, QStringList sharedFolders,
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
        pid  = connection().interface()->servicePid(message().service()).value();
        from = m_appForPid ? m_appForPid(pid) : QString();
    }

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
        } else {
            const QVariantMap map = resource.toMap();
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

    const bool textOnly =
        std::all_of(items.cbegin(), items.cend(), [](const Item &i) { return i.hostPath.isEmpty(); });
    QString type = mimeType;
    if (type.isEmpty())
        type = textOnly ? QStringLiteral("text/plain") :
                          QMimeDatabase().mimeTypeForFile(items.first().hostPath).name();

    m_title    = title;
    m_mimeType = type;
    m_items    = items;
    QVariantMap request{{QStringLiteral("title"), title},
                        {QStringLiteral("mimeType"), type},
                        {QStringLiteral("count"), items.size()},
                        {QStringLiteral("targets"), targetsFor(type, from, textOnly)}};
    for (const Item &item : std::as_const(items)) {
        if (!item.text.isEmpty() && !request.contains(QStringLiteral("text")))
            request.insert(QStringLiteral("text"), item.text.left(500));
        if (!item.hostPath.isEmpty() && !request.contains(QStringLiteral("image")) &&
            QMimeDatabase().mimeTypeForFile(item.hostPath).name().startsWith(
                QLatin1String("image/")))
            request.insert(QStringLiteral("image"), QUrl::fromLocalFile(item.hostPath).toString());
    }
    emit requested(request);
}

QVariantList ShareService::targetsFor(const QString &mimeType, const QString &from, bool textOnly) {
    m_targets.clear();
    QVariantList out;
    const QStringList ids = m_apps ? m_apps->getAllAppIds() : QStringList();
    for (const QString &appId : ids) {
        const MarathonAppRegistry::AppInfo *info = m_apps->getAppInfo(appId);
        if (!info || appId == from)
            continue;
        QFile manifest(info->absolutePath + QStringLiteral("/manifest.json"));
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
                               {QStringLiteral("name"), info->name},
                               {QStringLiteral("action"), method.value(QStringLiteral("title")).toString()},
                               {QStringLiteral("icon"), info->icon}};
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
        if (item.hostPath.isEmpty())
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
    if (m_raise)
        m_raise(target.appId);
    deliver(target.id, target.appId, target.method, configuration, 0);
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
