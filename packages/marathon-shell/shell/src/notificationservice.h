#ifndef NOTIFICATIONSERVICE_H
#define NOTIFICATIONSERVICE_H

#include <QObject>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include "notificationmodel.h"

class NotificationService : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

public:
    explicit NotificationService(NotificationModel* model, QObject* parent = nullptr);
    ~NotificationService();

    bool registerService();

public slots:
    Q_SCRIPTABLE uint Notify(const QString& appName, uint replacesId,
                             const QString& appIcon, const QString& summary,
                             const QString& body, const QStringList& actions,
                             const QVariantMap& hints, int timeout);
    
    Q_SCRIPTABLE void CloseNotification(uint id);
    
    Q_SCRIPTABLE QStringList GetCapabilities();
    
    Q_SCRIPTABLE void GetServerInformation(QString& name, QString& vendor,
                                           QString& version, QString& specVersion);

signals:
    Q_SCRIPTABLE void NotificationClosed(uint id, uint reason);
    Q_SCRIPTABLE void ActionInvoked(uint id, const QString& actionKey);

private:
    NotificationModel* m_model;
    uint m_nextId;
};

#endif // NOTIFICATIONSERVICE_H

