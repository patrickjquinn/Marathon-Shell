#include "notificationservice.h"
#include <QDebug>
#include <QDBusError>
#include <QTimer>

NotificationService::NotificationService(NotificationModel* model, QObject* parent)
    : QDBusAbstractAdaptor(parent)
    , m_model(model)
    , m_nextId(1)
{
    qDebug() << "[NotificationService] Initializing D-Bus notification daemon";
}

NotificationService::~NotificationService()
{
    qDebug() << "[NotificationService] Shutting down";
}

bool NotificationService::registerService()
{
    QDBusConnection sessionBus = QDBusConnection::sessionBus();
    
    if (!sessionBus.registerService("org.freedesktop.Notifications")) {
        qDebug() << "[NotificationService] Failed to register service:" 
                 << sessionBus.lastError().message();
        return false;
    }
    
    if (!sessionBus.registerObject("/org/freedesktop/Notifications", parent())) {
        qDebug() << "[NotificationService] Failed to register object:" 
                 << sessionBus.lastError().message();
        sessionBus.unregisterService("org.freedesktop.Notifications");
        return false;
    }
    
    qDebug() << "[NotificationService] Registered as org.freedesktop.Notifications";
    return true;
}

uint NotificationService::Notify(const QString& appName, uint replacesId,
                                 const QString& appIcon, const QString& summary,
                                 const QString& body, const QStringList& actions,
                                 const QVariantMap& hints, int timeout)
{
    qDebug() << "[NotificationService] Notify called:"
             << "app=" << appName
             << "summary=" << summary
             << "body=" << body
             << "icon=" << appIcon;
    
    uint id = (replacesId > 0) ? replacesId : m_nextId++;
    
    m_model->addNotification(appName, summary, body, appIcon);
    
    if (timeout > 0) {
        QTimer::singleShot(timeout, [this, id]() {
            emit NotificationClosed(id, 1);
        });
    }
    
    return id;
}

void NotificationService::CloseNotification(uint id)
{
    qDebug() << "[NotificationService] CloseNotification called: id=" << id;
    m_model->dismissNotification(id);
    emit NotificationClosed(id, 3);
}

QStringList NotificationService::GetCapabilities()
{
    return QStringList{
        "body",
        "body-markup",
        "icon-static",
        "actions",
        "persistence"
    };
}

void NotificationService::GetServerInformation(QString& name, QString& vendor,
                                               QString& version, QString& specVersion)
{
    name = "Marathon Shell";
    vendor = "Marathon OS";
    version = "1.0.0";
    specVersion = "1.2";
}

