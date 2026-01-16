#include "freedesktopnotifications.h"
#include "notificationmodel.h"
#include "powermanagercpp.h"
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDateTime>
#include <QDebug>
#include <QCoreApplication>
#include <QTimer>

FreedesktopNotifications::FreedesktopNotifications(NotificationDatabase *database,
                                                   NotificationModel    *model,
                                                   PowerManagerCpp *powerManager, QObject *parent)
    : QObject(parent)
    , m_database(database)
    , m_model(model)
    , m_powerManager(powerManager) {}

FreedesktopNotifications::~FreedesktopNotifications() {}

bool FreedesktopNotifications::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.freedesktop.Notifications")) {
        qDebug() << "[FreedesktopNotifications] org.freedesktop.Notifications already registered "
                    "(desktop environment)";

        if (bus.registerService("org.marathon.Notifications")) {
            qInfo() << "[FreedesktopNotifications] ✓ Registered fallback service: "
                       "org.marathon.Notifications";

            if (!bus.registerObject("/org/freedesktop/Notifications", this,
                                    QDBusConnection::ExportAllSlots |
                                        QDBusConnection::ExportAllSignals)) {
                qWarning() << "[FreedesktopNotifications] Failed to register object on fallback:"
                           << bus.lastError().message();
                return false;
            }
            return true;
        }

        qDebug() << "[FreedesktopNotifications] This is expected on desktop and will work on "
                    "actual device";
        return false;
    }

    if (!bus.registerObject("/org/freedesktop/Notifications", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qWarning() << "[FreedesktopNotifications] Failed to register object:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[FreedesktopNotifications] ✓ Registered org.freedesktop.Notifications on D-Bus";
    return true;
}

uint FreedesktopNotifications::Notify(const QString &app_name, uint replaces_id,
                                      const QString &app_icon, const QString &summary,
                                      const QString &body, const QStringList &actions,
                                      const QVariantMap &hints, int expire_timeout) {
    QString appId = extractAppName(app_name, hints);

    qInfo() << "[FreedesktopNotifications] Notify from:" << appId << "title:" << summary;

    if (replaces_id > 0) {
        m_database->dismiss(replaces_id);
        if (m_model) {
            m_model->dismissNotification(replaces_id);
        }
    }

    NotificationDatabase::NotificationRecord record;
    record.appId     = appId;
    record.title     = summary;
    record.body      = body;
    record.iconPath  = app_icon;
    record.timestamp = QDateTime::currentDateTime();
    record.read      = false;
    record.dismissed = false;

    record.metadata                   = hints;
    record.metadata["expire_timeout"] = expire_timeout;

    if (hints.contains("category")) {
        record.category = hints.value("category").toString();
    } else {
        record.category = "general";
    }

    record.priority = mapUrgencyToPriority(hints);

    int urgency = hints.value("urgency", 1).toInt();
    if (urgency >= 2 && m_powerManager) {
        m_powerManager->acquireWakelock("notification");
        qInfo() << "[FreedesktopNotifications] Acquired wakelock for critical notification";

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
            action["key"]   = actions[i];
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

void FreedesktopNotifications::CloseNotification(uint id) {
    qDebug() << "[FreedesktopNotifications] CloseNotification:" << id;

    if (m_database->dismiss(id)) {
        emit NotificationClosed(id, 3);
    }
}

QStringList FreedesktopNotifications::GetCapabilities() {

    return QStringList{"actions",     "body",         "body-markup", "icon-static",
                       "persistence", "action-icons", "inline-reply"};
}

void FreedesktopNotifications::InvokeReply(uint id, const QString &text) {
    qInfo() << "[FreedesktopNotifications] InvokeReply:" << id << "text:" << text;
    emit NotificationReplied(id, text);

    emit ActionInvoked(id, "inline-reply");
}

void FreedesktopNotifications::GetServerInformation(QString &name, QString &vendor,
                                                    QString &version, QString &spec_version) {
    name    = "Marathon Notification Service";
    vendor  = "Marathon OS";
    version = QCoreApplication::applicationVersion();
    if (version.isEmpty()) {
        version = "1.0.0";
    }
    spec_version = "1.2";

    qDebug() << "[FreedesktopNotifications] GetServerInformation called";
}

QString FreedesktopNotifications::extractAppName(const QString     &provided,
                                                 const QVariantMap &hints) {

    if (hints.contains("desktop-entry")) {
        QString desktopEntry = hints.value("desktop-entry").toString();
        if (!desktopEntry.isEmpty()) {
            return desktopEntry;
        }
    }

    if (!provided.isEmpty()) {
        return provided;
    }

    if (calledFromDBus()) {
        return message().service();
    }

    return "unknown";
}

int FreedesktopNotifications::mapUrgencyToPriority(const QVariantMap &hints) {

    if (hints.contains("urgency")) {
        int urgency = hints.value("urgency").toInt();
        switch (urgency) {
            case 0: return 0;
            case 1: return 1;
            case 2: return 3;
            default: return 1;
        }
    }

    return 1;
}
