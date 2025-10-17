#pragma once

#include <QObject>
#include <QSettings>
#include <QVariant>
#include <QStringList>

class SettingsManager : public QObject {
    Q_OBJECT
    
    // Existing properties
    Q_PROPERTY(qreal userScaleFactor READ userScaleFactor WRITE setUserScaleFactor NOTIFY userScaleFactorChanged)
    Q_PROPERTY(QString wallpaperPath READ wallpaperPath WRITE setWallpaperPath NOTIFY wallpaperPathChanged)
    
    // Migrated from QML SettingsManager
    Q_PROPERTY(QString deviceName READ deviceName WRITE setDeviceName NOTIFY deviceNameChanged)
    Q_PROPERTY(bool autoLock READ autoLock WRITE setAutoLock NOTIFY autoLockChanged)
    Q_PROPERTY(int autoLockTimeout READ autoLockTimeout WRITE setAutoLockTimeout NOTIFY autoLockTimeoutChanged)
    Q_PROPERTY(bool showNotificationPreviews READ showNotificationPreviews WRITE setShowNotificationPreviews NOTIFY showNotificationPreviewsChanged)
    Q_PROPERTY(QString timeFormat READ timeFormat WRITE setTimeFormat NOTIFY timeFormatChanged)
    Q_PROPERTY(QString dateFormat READ dateFormat WRITE setDateFormat NOTIFY dateFormatChanged)
    
    // Audio properties
    Q_PROPERTY(QString ringtone READ ringtone WRITE setRingtone NOTIFY ringtoneChanged)
    Q_PROPERTY(QString notificationSound READ notificationSound WRITE setNotificationSound NOTIFY notificationSoundChanged)
    Q_PROPERTY(QString alarmSound READ alarmSound WRITE setAlarmSound NOTIFY alarmSoundChanged)
    
    // Display properties
    Q_PROPERTY(int screenTimeout READ screenTimeout WRITE setScreenTimeout NOTIFY screenTimeoutChanged)
    Q_PROPERTY(bool autoBrightness READ autoBrightness WRITE setAutoBrightness NOTIFY autoBrightnessChanged)
    
    // Notification properties
    Q_PROPERTY(bool showNotificationsOnLockScreen READ showNotificationsOnLockScreen WRITE setShowNotificationsOnLockScreen NOTIFY showNotificationsOnLockScreenChanged)

public:
    explicit SettingsManager(QObject *parent = nullptr);
    ~SettingsManager() override = default;

    // Existing getters
    qreal userScaleFactor() const { return m_userScaleFactor; }
    QString wallpaperPath() const { return m_wallpaperPath; }
    
    // Migrated getters
    QString deviceName() const { return m_deviceName; }
    bool autoLock() const { return m_autoLock; }
    int autoLockTimeout() const { return m_autoLockTimeout; }
    bool showNotificationPreviews() const { return m_showNotificationPreviews; }
    QString timeFormat() const { return m_timeFormat; }
    QString dateFormat() const { return m_dateFormat; }
    
    // Audio getters
    QString ringtone() const { return m_ringtone; }
    QString notificationSound() const { return m_notificationSound; }
    QString alarmSound() const { return m_alarmSound; }
    
    // Display getters
    int screenTimeout() const { return m_screenTimeout; }
    bool autoBrightness() const { return m_autoBrightness; }
    
    // Notification getters
    bool showNotificationsOnLockScreen() const { return m_showNotificationsOnLockScreen; }

    // Existing setters
    void setUserScaleFactor(qreal factor);
    void setWallpaperPath(const QString &path);
    
    // Migrated setters
    void setDeviceName(const QString &name);
    void setAutoLock(bool enabled);
    void setAutoLockTimeout(int seconds);
    void setShowNotificationPreviews(bool show);
    void setTimeFormat(const QString &format);
    void setDateFormat(const QString &format);
    
    // Audio setters
    void setRingtone(const QString &path);
    void setNotificationSound(const QString &path);
    void setAlarmSound(const QString &path);
    
    // Display setters
    void setScreenTimeout(int ms);
    void setAutoBrightness(bool enabled);
    
    // Notification setters
    void setShowNotificationsOnLockScreen(bool enabled);

    // Invokable methods for sound lists
    Q_INVOKABLE QStringList availableRingtones();
    Q_INVOKABLE QStringList availableNotificationSounds();
    Q_INVOKABLE QStringList availableAlarmSounds();
    Q_INVOKABLE QStringList screenTimeoutOptions();
    Q_INVOKABLE int screenTimeoutValue(const QString &option);
    Q_INVOKABLE QString formatSoundName(const QString &path);

    // Existing invokables
    Q_INVOKABLE QVariant get(const QString &key, const QVariant &defaultValue = QVariant());
    Q_INVOKABLE void set(const QString &key, const QVariant &value);
    Q_INVOKABLE void sync();

signals:
    // Existing signals
    void userScaleFactorChanged();
    void wallpaperPathChanged();
    
    // Migrated signals
    void deviceNameChanged();
    void autoLockChanged();
    void autoLockTimeoutChanged();
    void showNotificationPreviewsChanged();
    void timeFormatChanged();
    void dateFormatChanged();
    
    // Audio signals
    void ringtoneChanged();
    void notificationSoundChanged();
    void alarmSoundChanged();
    
    // Display signals
    void screenTimeoutChanged();
    void autoBrightnessChanged();
    
    // Notification signals
    void showNotificationsOnLockScreenChanged();

private:
    void load();
    void save();

    QSettings m_settings;
    
    // Existing members
    qreal m_userScaleFactor;
    QString m_wallpaperPath;
    
    // Migrated members
    QString m_deviceName;
    bool m_autoLock;
    int m_autoLockTimeout;
    bool m_showNotificationPreviews;
    QString m_timeFormat;
    QString m_dateFormat;
    
    // Audio members
    QString m_ringtone;
    QString m_notificationSound;
    QString m_alarmSound;
    
    // Display members
    int m_screenTimeout;
    bool m_autoBrightness;
    
    // Notification members
    bool m_showNotificationsOnLockScreen;
};
