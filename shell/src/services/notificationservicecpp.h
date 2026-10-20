#ifndef NOTIFICATIONSERVICECPP_H
#define NOTIFICATIONSERVICECPP_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QPointer>
#include <qqml.h>

class NotificationModel;
class SettingsManager;
class AudioPolicyController;
class Haptics;

class NotificationServiceCpp : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(NotificationService)
    QML_SINGLETON
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(bool notificationsEnabled READ notificationsEnabled WRITE setNotificationsEnabled
                   NOTIFY notificationsEnabledChanged)
    Q_PROPERTY(bool soundEnabled READ soundEnabled WRITE setSoundEnabled NOTIFY soundEnabledChanged)
    Q_PROPERTY(bool vibrationEnabled READ vibrationEnabled WRITE setVibrationEnabled NOTIFY
                   vibrationEnabledChanged)
    Q_PROPERTY(bool isDndEnabled READ isDndEnabled NOTIFY isDndEnabledChanged)

  public:
    explicit NotificationServiceCpp(NotificationModel *model, SettingsManager *settings,
                                    AudioPolicyController *audioPolicy, Haptics *haptics,
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
    bool                     isDndEnabled() const;

    Q_INVOKABLE int          sendNotification(const QString &appId, const QString &title,
                                              const QString     &body,
                                              const QVariantMap &options = QVariantMap());
    Q_INVOKABLE void         dismissNotification(int id);
    Q_INVOKABLE void         dismissAllNotifications();
    Q_INVOKABLE void         markAsRead(int id);
    Q_INVOKABLE void         clearAll();
    Q_INVOKABLE void         clickNotification(int id);
    // An action button: the D-Bus server tells the sender and closes it.
    Q_INVOKABLE void         triggerAction(int id, const QString &action);
    Q_INVOKABLE QVariantMap  getNotification(int id) const;
    Q_INVOKABLE QVariantList getUnreadNotifications() const;
    Q_INVOKABLE int          getNotificationCountForApp(const QString &appId) const;

    void                     setNotificationsEnabled(bool enabled);
    void                     setSoundEnabled(bool enabled);
    void                     setVibrationEnabled(bool enabled);

  signals:
    void notificationsChanged();
    void unreadCountChanged();
    void notificationsEnabledChanged();
    void soundEnabledChanged();
    void vibrationEnabledChanged();
    void isDndEnabledChanged();

    void notificationReceived(const QVariantMap &notification);
    void notificationDismissed(int id);
    // A tap ("default") or a button, before notificationClicked or
    // notificationActionTriggered, so the sender hears of it before the
    // shell's handling closes the notification.
    void notificationActivated(int id, const QString &action);
    void notificationClicked(int id);
    void notificationActionTriggered(int id, const QString &action);

  private slots:
    void onNotificationAdded(int id);
    void onNotificationDismissed(int id);
    void onUnreadCountChanged();
    void onDndChanged();

  private:
    QVariantMap        buildNotificationMapFromModel(class Notification *notification) const;
    // sound false: the sender asked for none (freedesktop suppress-sound).
    void               playFeedbackIfNeeded(bool sound);
    void               removeNotificationById(int id);

    NotificationModel *m_model    = nullptr;
    SettingsManager   *m_settings = nullptr;
    QPointer<AudioPolicyController> m_audioPolicy;
    QPointer<Haptics>               m_haptics;

    QVariantList                    m_notifications;
    QHash<int, QVariantMap>         m_notificationMeta;
    QVariantMap                     m_pendingMeta;

    bool                            m_notificationsEnabled = true;
    bool                            m_soundEnabled         = true;
    bool                            m_vibrationEnabled     = true;
};

#endif
