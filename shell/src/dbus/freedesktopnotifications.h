#ifndef FREEDESKTOPNOTIFICATIONS_H
#define FREEDESKTOPNOTIFICATIONS_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>
#include <QStringList>
#include <QVariantMap>
#include "notificationdatabase.h"

/**
 * @brief Standard org.freedesktop.Notifications implementation
 * 
 * Implements the freedesktop.org notification specification for compatibility
 * with 3rd-party applications. Bridges to Marathon's internal notification system.
 * 
 * Spec: https://specifications.freedesktop.org/notification-spec/
 */
class FreedesktopNotifications : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

public:
    explicit FreedesktopNotifications(NotificationDatabase *database, QObject *parent = nullptr);
    ~FreedesktopNotifications();

    bool registerService();

public slots:
    // Standard freedesktop.org Notifications interface methods
    
    /**
     * Sends a notification
     * @param app_name Application name
     * @param replaces_id ID of notification to replace (0 for new)
     * @param app_icon Icon name or file path
     * @param summary Notification title
     * @param body Notification body text
     * @param actions Array of action IDs and labels
     * @param hints Additional metadata
     * @param expire_timeout Timeout in milliseconds (-1 = default, 0 = never)
     * @return Notification ID
     */
    uint Notify(const QString &app_name,
                uint replaces_id,
                const QString &app_icon,
                const QString &summary,
                const QString &body,
                const QStringList &actions,
                const QVariantMap &hints,
                int expire_timeout);
    
    /**
     * Closes a notification
     * @param id Notification ID to close
     */
    void CloseNotification(uint id);
    
    /**
     * Gets server capabilities
     * @return List of supported capabilities
     */
    QStringList GetCapabilities();
    
    /**
     * Gets server information
     * @param name Server name
     * @param vendor Server vendor
     * @param version Server version
     * @param spec_version Spec version implemented
     */
    void GetServerInformation(QString &name, QString &vendor, QString &version, QString &spec_version);

signals:
    // Standard freedesktop.org signals
    
    /**
     * Emitted when a notification is closed
     * @param id Notification ID
     * @param reason Reason code (1=expired, 2=dismissed by user, 3=closed by call, 4=undefined)
     */
    void NotificationClosed(uint id, uint reason);
    
    /**
     * Emitted when an action is invoked
     * @param id Notification ID
     * @param action_key Action key that was invoked
     */
    void ActionInvoked(uint id, const QString &action_key);

private:
    NotificationDatabase *m_database;
    
    /**
     * Extract app name from hints or use provided name
     */
    QString extractAppName(const QString &provided, const QVariantMap &hints);
    
    /**
     * Map freedesktop urgency to Marathon priority
     */
    int mapUrgencyToPriority(const QVariantMap &hints);
};

#endif // FREEDESKTOPNOTIFICATIONS_H

