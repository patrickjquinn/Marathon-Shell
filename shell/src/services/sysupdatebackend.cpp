#include "sysupdatebackend.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QUrl>
#include <QXmlStreamReader>

#include <cstring>
#include <functional>

namespace {
    constexpr auto kService      = QLatin1StringView("org.freedesktop.sysupdate1");
    constexpr auto kManagerPath  = QLatin1StringView("/org/freedesktop/sysupdate1");
    constexpr auto kManagerIface = QLatin1StringView("org.freedesktop.sysupdate1.Manager");
    constexpr auto kTargetIface  = QLatin1StringView("org.freedesktop.sysupdate1.Target");
    constexpr auto kJobIface     = QLatin1StringView("org.freedesktop.sysupdate1.Job");
    // CheckNew and Install fetch SHA256SUMS over the network before replying.
    constexpr int kNetworkCallTimeoutMs = 120 * 1000;

    void call(QObject *context, const QString &path, QLatin1StringView iface, const QString &method,
              const QVariantList &args, const std::function<void(const QDBusMessage &)> &onReply,
              const std::function<void(const QString &)> &onError, int timeoutMs = -1) {
        QDBusMessage msg = QDBusMessage::createMethodCall(kService, path, iface, method);
        msg.setArguments(args);
        msg.setInteractiveAuthorizationAllowed(true);
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::systemBus().asyncCall(msg, timeoutMs), context);
        QObject::connect(watcher, &QDBusPendingCallWatcher::finished, context,
                         [watcher, onReply, onError]() {
                             watcher->deleteLater();
                             const QDBusMessage reply = watcher->reply();
                             if (reply.type() == QDBusMessage::ErrorMessage)
                                 onError(reply.errorMessage());
                             else
                                 onReply(reply);
                         });
    }
} // namespace

SysupdateBackend::SysupdateBackend(QObject *parent)
    : UpdateBackend(parent)
    , m_net(new QNetworkAccessManager(this)) {
    QDBusConnection::systemBus().connect(kService, kManagerPath, kManagerIface,
                                         QStringLiteral("JobRemoved"), this,
                                         SLOT(onJobRemoved(qulonglong, QDBusObjectPath, int)));
}

void SysupdateBackend::probe() {
    call(
        this, kManagerPath, kManagerIface, QStringLiteral("ListTargets"), {},
        [this](const QDBusMessage &reply) {
            const QDBusArgument targets = reply.arguments().value(0).value<QDBusArgument>();
            targets.beginArray();
            while (!targets.atEnd()) {
                QString         cls, name;
                QDBusObjectPath path;
                targets.beginStructure();
                targets >> cls >> name >> path;
                targets.endStructure();
                if (cls == QLatin1String("host"))
                    m_target = path.path();
            }
            targets.endArray();
            if (m_target.isEmpty()) {
                emit probed(false, {});
                return;
            }
            call(
                this, m_target, kTargetIface, QStringLiteral("GetVersion"), {},
                [this](const QDBusMessage &r) {
                    emit probed(true, r.arguments().value(0).toString());
                },
                [this](const QString &error) {
                    qWarning() << "[SysupdateBackend] GetVersion:" << error;
                    emit probed(true, {});
                });
        },
        [this](const QString &error) {
            qInfo() << "[SysupdateBackend] no update service:" << error;
            emit probed(false, {});
        });
}

void SysupdateBackend::checkNew() {
    call(
        this, m_target, kTargetIface, QStringLiteral("CheckNew"), {},
        [this](const QDBusMessage &reply) { emit checked(reply.arguments().value(0).toString()); },
        [this](const QString &error) { emit failed(error); }, kNetworkCallTimeoutMs);
}

void SysupdateBackend::fetchReleaseInfo(const QString &version) {
    call(
        this, m_target, kTargetIface, QStringLiteral("GetAppStream"), {},
        [this, version](const QDBusMessage &reply) {
            const QStringList urls = reply.arguments().value(0).toStringList();
            if (urls.isEmpty()) {
                emit releaseInfo(version, -1, {});
                return;
            }
            QNetworkRequest req{QUrl(urls.first())};
            req.setTransferTimeout(30 * 1000);
            QNetworkReply *net = m_net->get(req);
            connect(net, &QNetworkReply::finished, this, [this, net, version]() {
                net->deleteLater();
                if (net->error() != QNetworkReply::NoError) {
                    qWarning() << "[SysupdateBackend] AppStream:" << net->errorString();
                    emit releaseInfo(version, -1, {});
                    return;
                }
                const Release r = parseAppStream(net->readAll(), version);
                emit          releaseInfo(version, r.downloadSize, r.notes);
            });
        },
        [this, version](const QString &error) {
            qWarning() << "[SysupdateBackend] GetAppStream:" << error;
            emit releaseInfo(version, -1, {});
        });
}

void SysupdateBackend::install() {
    call(
        this, m_target, kTargetIface, QStringLiteral("Install"),
        {QString(), QVariant::fromValue(qulonglong(0))},
        [this](const QDBusMessage &reply) {
            const QVariantList args = reply.arguments();
            m_installingVersion     = args.value(0).toString();
            m_jobId                 = args.value(1).toULongLong();
            m_jobPath               = args.value(2).value<QDBusObjectPath>().path();
            QDBusConnection::systemBus().connect(
                kService, m_jobPath, QStringLiteral("org.freedesktop.DBus.Properties"),
                QStringLiteral("PropertiesChanged"), this,
                SLOT(onJobPropertiesChanged(QString, QVariantMap, QStringList)));
        },
        [this](const QString &error) { emit failed(error); }, kNetworkCallTimeoutMs);
}

void SysupdateBackend::cancel() {
    if (m_jobPath.isEmpty())
        return;
    call(
        this, m_jobPath, kJobIface, QStringLiteral("Cancel"), {}, [](const QDBusMessage &) {},
        [](const QString &error) { qWarning() << "[SysupdateBackend] Cancel:" << error; });
}

void SysupdateBackend::onJobPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                              const QStringList &) {
    if (interface == kJobIface && changed.contains(QStringLiteral("Progress")))
        emit progress(int(changed.value(QStringLiteral("Progress")).toUInt()));
}

void SysupdateBackend::onJobRemoved(qulonglong id, const QDBusObjectPath &path, int status) {
    if (id != m_jobId || m_jobPath.isEmpty())
        return;
    QDBusConnection::systemBus().disconnect(
        kService, path.path(), QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"), this,
        SLOT(onJobPropertiesChanged(QString, QVariantMap, QStringList)));
    m_jobPath.clear();
    m_jobId = 0;
    if (status == 0)
        emit installed(m_installingVersion);
    else
        emit failed(status > 0 ?
                        QStringLiteral("systemd-sysupdate exited with status %1").arg(status) :
                        QString::fromLocal8Bit(strerror(-status)));
}

SysupdateBackend::Release SysupdateBackend::parseAppStream(const QByteArray &xml,
                                                           const QString    &version) {
    Release          release;
    QStringList      notes;
    QXmlStreamReader r(xml);
    bool             inRelease = false;
    while (!r.atEnd()) {
        r.readNext();
        if (r.isStartElement()) {
            if (r.name() == QLatin1String("release")) {
                inRelease = r.attributes().value(QLatin1String("version")) == version;
            } else if (inRelease && r.name() == QLatin1String("size") &&
                       r.attributes().value(QLatin1String("type")) == QLatin1String("download")) {
                bool         ok   = false;
                const qint64 size = r.readElementText().trimmed().toLongLong(&ok);
                if (ok)
                    release.downloadSize = qMax<qint64>(release.downloadSize, 0) + size;
            } else if (inRelease && r.name() == QLatin1String("p")) {
                notes << r.readElementText().simplified();
            } else if (inRelease && r.name() == QLatin1String("li")) {
                notes << QStringLiteral("• ") + r.readElementText().simplified();
            }
        } else if (r.isEndElement() && r.name() == QLatin1String("release")) {
            inRelease = false;
        }
    }
    if (r.hasError())
        return {};
    release.notes = notes.join(QLatin1Char('\n'));
    return release;
}

UpdateConditions SysupdateBackend::systemConditions() {
    UpdateConditions c;
    QDBusInterface   nm(QStringLiteral("org.freedesktop.NetworkManager"),
                        QStringLiteral("/org/freedesktop/NetworkManager"),
                        QStringLiteral("org.freedesktop.NetworkManager"),
                        QDBusConnection::systemBus());
    c.metered = nm.property("Metered").toUInt();
    QDBusInterface battery(QStringLiteral("org.freedesktop.UPower"),
                           QStringLiteral("/org/freedesktop/UPower/devices/DisplayDevice"),
                           QStringLiteral("org.freedesktop.UPower.Device"),
                           QDBusConnection::systemBus());
    c.batteryPresent = battery.property("IsPresent").toBool();
    c.batteryPercent = battery.property("Percentage").toDouble();
    c.batteryState   = battery.property("State").toUInt();
    return c;
}
