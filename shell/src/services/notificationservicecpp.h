#ifndef NOTIFICATIONSERVICECPP_H
#define NOTIFICATIONSERVICECPP_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QPointer>

class NotificationModel;
class SettingsManager;
class AudioPolicyController;
class HapticManager;

class NotificationServiceCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(bool notificationsEnabled READ notificationsEnabled WRITE setNotificationsEnabled
                   NOTIFY notificationsEnabledChanged)
    Q_PROPERTY(bool soundEnabled READ soundEnabled WRITE setSoundEnabled NOTIFY soundEnabledChanged)
    Q_PROPERTY(bool vibrationEnabled READ vibrationEnabled WRITE setVibrationEnabled NOTIFY
                   vibrationEnabledChanged)
    Q_PROPERTY(bool ledEnabled READ ledEnabled WRITE setLedEnabled NOTIFY ledEnabledChanged)
    Q_PROPERTY(bool isDndEnabled READ isDndEnabled NOTIFY isDndEnabledChanged)

  public:
    explicit NotificationServiceCpp(NotificationModel *model, SettingsManager *settings,
                                    AudioPolicyController *audioPolicy, HapticManager *haptics,
                                    QObject *parent = nullptr);

    QVariantList notifications() const {
        return m_notifications;
    }
    int  unreadCount() const;
    bool notificationsEnabled() const {
        return m_notificationsEnabled;
    }
    bool soundEnabled() const {
        return m_soundEnabled;
    }
    bool vibrationEnabled() const {
        return m_vibrationEnabled;
    }
    bool ledEnabled() const {
        return m_ledEnabled;
    }
    bool                     isDndEnabled() const;

    Q_INVOKABLE int          sendNotification(const QString &appId, const QString &title,
                                              const QString     &body,
                                              const QVariantMap &options = QVariantMap());
    Q_INVOKABLE void         dismissNotification(int id);
    Q_INVOKABLE void         dismissAllNotifications();
    Q_INVOKABLE void         markAsRead(int id);
    Q_INVOKABLE void         markAllAsRead();
    Q_INVOKABLE void         clearAll();
    Q_INVOKABLE void         clickNotification(int id);
    Q_INVOKABLE void         triggerAction(int id, const QString &action);
    Q_INVOKABLE QVariantMap  getNotification(int id) const;
    Q_INVOKABLE QVariantList getNotificationsByApp(const QString &appId) const;
    Q_INVOKABLE QVariantList getUnreadNotifications() const;
    Q_INVOKABLE int          getNotificationCountForApp(const QString &appId) const;

    void                     setNotificationsEnabled(bool enabled);
    void                     setSoundEnabled(bool enabled);
    void                     setVibrationEnabled(bool enabled);
    void                     setLedEnabled(bool enabled);

  signals:
    void notificationsChanged();
    void unreadCountChanged();
    void notificationsEnabledChanged();
    void soundEnabledChanged();
    void vibrationEnabledChanged();
    void ledEnabledChanged();
    void isDndEnabledChanged();

    void notificationReceived(const QVariantMap &notification);
    void notificationDismissed(int id);
    void notificationClicked(int id);
    void notificationActionTriggered(int id, const QString &action);

  private slots:
    void onNotificationAdded(int id);
    void onNotificationDismissed(int id);
    void onUnreadCountChanged();
    void onDndChanged();

  private:
    QVariantMap        buildNotificationMapFromModel(class Notification *notification) const;
    void               playFeedbackIfNeeded();
    void               removeNotificationById(int id);

    NotificationModel *m_model    = nullptr;
    SettingsManager   *m_settings = nullptr;
    QPointer<AudioPolicyController> m_audioPolicy;
    QPointer<HapticManager>         m_haptics;

    QVariantList                    m_notifications;
    QHash<int, QVariantMap>         m_notificationMeta;

    bool                            m_notificationsEnabled = true;
    bool                            m_soundEnabled         = true;
    bool                            m_vibrationEnabled     = true;
    bool                            m_ledEnabled           = true;
};

#endif
