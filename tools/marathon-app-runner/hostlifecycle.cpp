#include "hostlifecycle.h"

#include "keelhost.h"

#include <QDBusConnectionInterface>
#include <QRegularExpression>

HostLifecycle::HostLifecycle(KeelHost *host, qint64 shellPid, QObject *parent)
    : QObject(parent)
    , m_host(host)
    , m_shellPid(shellPid) {}

QString HostLifecycle::serviceName(const QString &appId) {
    static const QRegularExpression nonIdentifier(QStringLiteral("[^A-Za-z0-9_]"));
    return QStringLiteral("org.marathonos.AppRunner.") +
        QString(appId).replace(nonIdentifier, QStringLiteral("_"));
}

bool HostLifecycle::registerOn(QDBusConnection bus, const QString &appId) {
    return bus.registerObject(QStringLiteral("/org/marathonos/AppRunner/Lifecycle"), this,
                              QDBusConnection::ExportAllSlots) &&
        bus.registerService(serviceName(appId));
}

void HostLifecycle::SetActive(bool active) {
    if (callerIsShell())
        m_host->setActive(active);
}

void HostLifecycle::SetCoverStatus(int status) {
    if (callerIsShell())
        m_host->setCoverStatus(status);
}

bool HostLifecycle::callerIsShell() {
    if (!calledFromDBus())
        return false;
    const auto pid = connection().interface()->servicePid(message().service());
    if (m_shellPid <= 0 || !pid.isValid() || static_cast<qint64>(pid.value()) != m_shellPid) {
        sendErrorReply(QDBusError::AccessDenied, QStringLiteral("Caller is not the shell"));
        return false;
    }
    return true;
}
