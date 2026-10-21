#ifndef FREEDESKTOPNOTIFICATIONS_H
#define FREEDESKTOPNOTIFICATIONS_H

#include <QObject>
#include <QPointer>
#include <QDBusContext>
#include <QDBusConnection>
#include <QHash>
#include <QStringList>
#include <QVariantMap>
#include "notificationdatabase.h"

class Apps;
class MarathonAppRegistry;
class NotificationModel;
class Power;
class QDBusServiceWatcher;

class FreedesktopNotifications : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

  public:
    explicit FreedesktopNotifications(NotificationDatabase *database, NotificationModel *model,
                                      Power *powerManager, QObject *parent = nullptr);
    ~FreedesktopNotifications() override;

    bool registerService();

    // Lets notifications name the installed app they came from.
    void setAppRegistry(MarathonAppRegistry *registry);
    // And the desktop apps the shell lists (flatpaks, Android apps).
    void setAppModel(Apps *apps);

    // A tap ("default") or an action button: tells the client, and makes the
    // D-Bus call a Nemo.Notifications client attached to that action.
    void activate(uint id, const QString &action);

  public slots:
    uint        Notify(const QString &app_name, uint replaces_id, const QString &app_icon,
                       const QString &summary, const QString &body, const QStringList &actions,
                       const QVariantMap &hints, int expire_timeout);

    void        CloseNotification(uint id);

    QStringList GetCapabilities();

    void        GetServerInformation(QString &name, QString &vendor, QString &version,
                                     QString &spec_version);

  signals:
    void NotificationClosed(uint id, uint reason);

    void ActionInvoked(uint id, const QString &action_key);

    void NotificationReplied(uint id, const QString &text);

    // A transient notification, shown as a banner but not kept.
    void bannerRequested(const QVariantMap &notification);
    // An app's toast (x-marathon-toast), shown at the bottom.
    void toastRequested(const QVariantMap &notification);

  public slots:
    void InvokeReply(uint id, const QString &text);

  private:
    NotificationDatabase *m_database;
    NotificationModel    *m_model;
    Power      *m_powerManager;
    QPointer<MarathonAppRegistry> m_registry;
    QPointer<Apps>                m_apps;
    // Transient notifications have ids no database row will reach.
    uint                          m_nextTransientId = 1u << 31;

    // The bus name that posted each ongoing notification.
    QHash<uint, QString>  m_senders;
    QDBusServiceWatcher  *m_senderWatcher = nullptr;

    void                  trackSender(uint id);
    void                  onSenderGone(const QString &sender);

    QString               extractAppName(const QString &provided, const QVariantMap &hints);

    int                   mapUrgencyToPriority(const QVariantMap &hints);
};

#endif
