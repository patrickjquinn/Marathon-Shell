#include "freedesktopnotifications.h"
#include "../notificationmodel.h"
#include "../powermanagercpp.h"
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDateTime>
#include <QDebug>
#include <QCoreApplication>
#include <QTimer>

FreedesktopNotifications::FreedesktopNotifications(NotificationDatabase *database, NotificationModel *model, PowerManagerCpp *powerManager, QObject *parent)
    : QObject(parent)
    , m_database(database)
    , m_model(model)
    , m_powerManager(powerManager)
{
}

FreedesktopNotifications::~FreedesktopNotifications()
{
}

bool FreedesktopNotifications::registerService()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    
    if (!bus.registerService("org.freedesktop.Notifications")) {
        qDebug() << "[FreedesktopNotifications] org.freedesktop.Notifications already registered (desktop environment)";
        
        // Fallback for nested testing: Register org.marathon.Notifications
        if (bus.registerService("org.marathon.Notifications")) {
            qInfo() << "[FreedesktopNotifications] ✓ Registered fallback service: org.marathon.Notifications";
            
            // Register the object path for the fallback service too
            if (!bus.registerObject("/org/freedesktop/Notifications", this,
                                   QDBusConnection::ExportAllSlots |
                                   QDBusConnection::ExportAllSignals)) {
                qWarning() << "[FreedesktopNotifications] Failed to register object on fallback:" << bus.lastError().message();
                return false;
            }
            return true;
        }
        
        qDebug() << "[FreedesktopNotifications] This is expected on desktop and will work on actual device";
        return false;
    }
    
    if (!bus.registerObject("/org/freedesktop/Notifications", this,
                           QDBusConnection::ExportAllSlots |
                           QDBusConnection::ExportAllSignals)) {
        qWarning() << "[FreedesktopNotifications] Failed to register object:" << bus.lastError().message();
        return false;
    }
    
    qInfo() << "[FreedesktopNotifications] ✓ Registered org.freedesktop.Notifications on D-Bus";
    return true;
}

uint FreedesktopNotifications::Notify(const QString &app_name,
                                      uint replaces_id,
                                      const QString &app_icon,
                                      const QString &summary,
                                      const QString &body,
                                      const QStringList &actions,
                                      const QVariantMap &hints,
                                      int expire_timeout)
{
    QString appId = extractAppName(app_name, hints);
    
    qInfo() << "[FreedesktopNotifications] Notify from:" << appId << "title:" << summary;
    
    if (replaces_id > 0) {
        m_database->dismiss(replaces_id);
        if (m_model) {
            m_model->dismissNotification(replaces_id);
        }
    }
    
    NotificationDatabase::NotificationRecord record;
    record.appId = appId;
    record.title = summary;
    record.body = body;
    record.iconPath = app_icon;
    record.timestamp = QDateTime::currentDateTime();
    record.read = false;
    record.dismissed = false;
    
    record.metadata = hints;
    record.metadata["expire_timeout"] = expire_timeout;
    
    if (hints.contains("category")) {
        record.category = hints.value("category").toString();
    } else {
        record.category = "general";
    }
    
    record.priority = mapUrgencyToPriority(hints);
    
    // Acquire temporary wakelock for high-priority notifications
    // Urgency: 0 = low, 1 = normal, 2 = critical
    int urgency = hints.value("urgency", 1).toInt();
    if (urgency >= 2 && m_powerManager) {
        m_powerManager->acquireWakelock("notification");
        qInfo() << "[FreedesktopNotifications] Acquired wakelock for critical notification";
        
        // Release after 5 seconds
        QTimer::singleShot(5000, this, [this]() {
            if (m_powerManager) {
                m_powerManager->releaseWakelock("notification");
                qInfo() << "[FreedesktopNotifications] Released notification wakelock";
            }
        });
    }
    
    QVariantList actionList;
    for (int i = 0; i < actions.size(); i += 2) {
        if (i + 1 < actions.size()) {
            QVariantMap action;
            action["key"] = actions[i];
            action["label"] = actions[i + 1];
            actionList.append(action);
        }
    }
    record.actions = actionList;
    
    uint id = m_database->saveNotification(record);
    
    if (m_model) {
        m_model->addNotification(appId, summary, body, app_icon);
    }
    
    if (expire_timeout > 0) {
        QTimer::singleShot(expire_timeout, this, [this, id]() {
            m_database->dismiss(id);
            if (m_model) {
                m_model->dismissNotification(id);
            }
            emit NotificationClosed(id, 1);
        });
    }
    
    return id;
}

void FreedesktopNotifications::CloseNotification(uint id)
{
    qDebug() << "[FreedesktopNotifications] CloseNotification:" << id;
    
    if (m_database->dismiss(id)) {
        emit NotificationClosed(id, 3); // Reason: closed by CloseNotification call
    }
}

QStringList FreedesktopNotifications::GetCapabilities()
{
    // Return list of supported capabilities
    // See: https://specifications.freedesktop.org/notification-spec/latest/ar01s08.html
    return QStringList{
        "actions",              // Supports notification actions
        "body",                 // Supports body text
        "body-markup",          // Supports markup in body (we strip it but declare support)
        "icon-static",          // Supports icon
        "persistence",          // Notifications persist
        "action-icons",         // Action icons supported
        "inline-reply"          // Inline reply support for quick responses
    };
}

void FreedesktopNotifications::InvokeReply(uint id, const QString &text)
{
    qInfo() << "[FreedesktopNotifications] InvokeReply:" << id << "text:" << text;
    emit NotificationReplied(id, text);
    
    // Emit ActionInvoked for compatibility with apps expecting "default" action
    emit ActionInvoked(id, "inline-reply");
}

void FreedesktopNotifications::GetServerInformation(QString &name, QString &vendor, QString &version, QString &spec_version)
{
    name = "Marathon Notification Service";
    vendor = "Marathon OS";
    version = QCoreApplication::applicationVersion();
    if (version.isEmpty()) {
        version = "1.0.0";
    }
    spec_version = "1.2"; // freedesktop.org notification spec version
    
    qDebug() << "[FreedesktopNotifications] GetServerInformation called";
}

QString FreedesktopNotifications::extractAppName(const QString &provided, const QVariantMap &hints)
{
    // Prefer desktop-entry from hints for proper app identification
    if (hints.contains("desktop-entry")) {
        QString desktopEntry = hints.value("desktop-entry").toString();
        if (!desktopEntry.isEmpty()) {
            return desktopEntry;
        }
    }
    
    // Fallback to provided app_name
    if (!provided.isEmpty()) {
        return provided;
    }
    
    // Last resort: try sender from DBus context
    if (calledFromDBus()) {
        return message().service();
    }
    
    return "unknown";
}

int FreedesktopNotifications::mapUrgencyToPriority(const QVariantMap &hints)
{
    // freedesktop urgency: 0=low, 1=normal, 2=critical
    // Marathon priority: 0=low, 1=normal, 2=high, 3=urgent
    
    if (hints.contains("urgency")) {
        int urgency = hints.value("urgency").toInt();
        switch (urgency) {
            case 0: return 0; // low -> low
            case 1: return 1; // normal -> normal
            case 2: return 3; // critical -> urgent
            default: return 1;
        }
    }
    
    return 1; // default: normal
}

