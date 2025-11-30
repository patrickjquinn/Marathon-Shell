#include "marathonpermissionportal.h"
#include "../marathonpermissionmanager.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusConnectionInterface>
#include <QDebug>
#include <QFile>
#include <QTextStream>

MarathonPermissionPortal::MarathonPermissionPortal(MarathonPermissionManager *permissionManager,
                                                   QObject                   *parent)
    : QObject(parent)
    , m_permissionManager(permissionManager) {
    // Connect permission manager signals to forward to D-Bus
    connect(m_permissionManager, &MarathonPermissionManager::permissionGranted, this,
            [this](const QString &appId, const QString &permission) {
                QString callerAppId = getCallerAppId();
                if (appId == callerAppId) {
                    emit PermissionGranted(permission);
                }
            });

    connect(m_permissionManager, &MarathonPermissionManager::permissionDenied, this,
            [this](const QString &appId, const QString &permission) {
                QString callerAppId = getCallerAppId();
                if (appId == callerAppId) {
                    emit PermissionDenied(permission);
                }
            });
}

bool MarathonPermissionPortal::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerObject("/org/marathonos/PermissionPortal", this,
                            QDBusConnection::ExportAllContents)) {
        qWarning() << "[MarathonPermissionPortal] Failed to register object";
        return false;
    }

    if (!bus.registerService("org.marathonos.PermissionPortal")) {
        qWarning() << "[MarathonPermissionPortal] Failed to register service";
        return false;
    }

    qDebug() << "[MarathonPermissionPortal] Service registered successfully";
    return true;
}

qint64 MarathonPermissionPortal::getCallerPid() {
    if (!calledFromDBus()) {
        return -1;
    }

    // Get caller's connection name
    QString callerService = message().service();

    // Get PID from D-Bus connection
    QDBusConnection  bus   = QDBusConnection::sessionBus();
    QDBusReply<uint> reply = bus.interface()->servicePid(callerService);

    if (reply.isValid()) {
        return static_cast<qint64>(reply.value());
    }

    qWarning() << "[MarathonPermissionPortal] Failed to get caller PID";
    return -1;
}

QString MarathonPermissionPortal::resolveAppIdFromPid(qint64 pid) {
    if (pid < 0) {
        return QString();
    }

    // Read /proc/[pid]/cmdline to get the command
    QString cmdlinePath = QString("/proc/%1/cmdline").arg(pid);
    QFile   file(cmdlinePath);

    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[MarathonPermissionPortal] Failed to read cmdline for PID:" << pid;
        return QString();
    }

    QString cmdline = QString::fromUtf8(file.readAll());
    file.close();

    // Replace null terminators with spaces
    cmdline.replace('\0', ' ');
    cmdline = cmdline.trimmed();

    qDebug() << "[MarathonPermissionPortal] Process command:" << cmdline << "PID:" << pid;

    // Try to extract app ID from command line
    // Marathon apps are typically loaded as: marathon-shell-bin <app-path>
    // Or if launched directly: qml <app-file>
    // For now, return a simplified version
    // TODO: Implement proper app ID resolution from TaskModel or process tracking

    if (cmdline.contains("marathon-shell")) {
        // This is the shell itself
        return "org.marathonos.Shell";
    }

    // For external apps, we'd need to track them properly
    // For now, return unknown
    return "unknown." + QString::number(pid);
}

QString MarathonPermissionPortal::getCallerAppId() {
    qint64 pid = getCallerPid();
    return resolveAppIdFromPid(pid);
}

bool MarathonPermissionPortal::CheckPermission(const QString &permission) {
    QString appId = getCallerAppId();

    if (appId.isEmpty()) {
        qWarning() << "[MarathonPermissionPortal] Failed to identify caller";
        return false;
    }

    bool hasPermission = m_permissionManager->hasPermission(appId, permission);

    qDebug() << "[MarathonPermissionPortal] Permission check:" << appId << permission
             << hasPermission;

    return hasPermission;
}

void MarathonPermissionPortal::RequestPermission(const QString &permission) {
    QString appId = getCallerAppId();

    if (appId.isEmpty()) {
        qWarning() << "[MarathonPermissionPortal] Failed to identify caller";
        return;
    }

    qDebug() << "[MarathonPermissionPortal] Permission request:" << appId << permission;

    m_permissionManager->requestPermission(appId, permission);
}

QString MarathonPermissionPortal::GetCallerAppId() {
    return getCallerAppId();
}
