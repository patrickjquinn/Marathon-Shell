#pragma once

#include <QObject>
#include <QSettings>
#include <QVariant>
#include <QStringList>

class SettingsManager : public QObject {
    Q_OBJECT

    // Existing properties
    Q_PROPERTY(qreal userScaleFactor READ userScaleFactor WRITE setUserScaleFactor NOTIFY
                   userScaleFactorChanged)
    Q_PROPERTY(
        QString wallpaperPath READ wallpaperPath WRITE setWallpaperPath NOTIFY wallpaperPathChanged)

    // Migrated from QML SettingsManager
    Q_PROPERTY(QString deviceName READ deviceName WRITE setDeviceName NOTIFY deviceNameChanged)
    Q_PROPERTY(bool autoLock READ autoLock WRITE setAutoLock NOTIFY autoLockChanged)
    Q_PROPERTY(int autoLockTimeout READ autoLockTimeout WRITE setAutoLockTimeout NOTIFY
                   autoLockTimeoutChanged)
    Q_PROPERTY(bool showNotificationPreviews READ showNotificationPreviews WRITE
                   setShowNotificationPreviews NOTIFY showNotificationPreviewsChanged)
    Q_PROPERTY(QString timeFormat READ timeFormat WRITE setTimeFormat NOTIFY timeFormatChanged)
    Q_PROPERTY(QString dateFormat READ dateFormat WRITE setDateFormat NOTIFY dateFormatChanged)

    // Audio properties
    Q_PROPERTY(QString ringtone READ ringtone WRITE setRingtone NOTIFY ringtoneChanged)
    Q_PROPERTY(QString notificationSound READ notificationSound WRITE setNotificationSound NOTIFY
                   notificationSoundChanged)
    Q_PROPERTY(QString alarmSound READ alarmSound WRITE setAlarmSound NOTIFY alarmSoundChanged)
    Q_PROPERTY(qreal mediaVolume READ mediaVolume WRITE setMediaVolume NOTIFY mediaVolumeChanged)
    Q_PROPERTY(qreal ringtoneVolume READ ringtoneVolume WRITE setRingtoneVolume NOTIFY
                   ringtoneVolumeChanged)
    Q_PROPERTY(qreal alarmVolume READ alarmVolume WRITE setAlarmVolume NOTIFY alarmVolumeChanged)
    Q_PROPERTY(qreal notificationVolume READ notificationVolume WRITE setNotificationVolume NOTIFY
                   notificationVolumeChanged)
    Q_PROPERTY(
        qreal systemVolume READ systemVolume WRITE setSystemVolume NOTIFY systemVolumeChanged)

    // Display properties
    Q_PROPERTY(
        int screenTimeout READ screenTimeout WRITE setScreenTimeout NOTIFY screenTimeoutChanged)
    Q_PROPERTY(bool autoBrightness READ autoBrightness WRITE setAutoBrightness NOTIFY
                   autoBrightnessChanged)
    Q_PROPERTY(QString statusBarClockPosition READ statusBarClockPosition WRITE
                   setStatusBarClockPosition NOTIFY statusBarClockPositionChanged)

    // Notification properties
    Q_PROPERTY(bool showNotificationsOnLockScreen READ showNotificationsOnLockScreen WRITE
                   setShowNotificationsOnLockScreen NOTIFY showNotificationsOnLockScreenChanged)

    // App management properties
    Q_PROPERTY(bool filterMobileFriendlyApps READ filterMobileFriendlyApps WRITE
                   setFilterMobileFriendlyApps NOTIFY filterMobileFriendlyAppsChanged)
    Q_PROPERTY(QStringList hiddenApps READ hiddenApps WRITE setHiddenApps NOTIFY hiddenAppsChanged)
    Q_PROPERTY(
        QString appSortOrder READ appSortOrder WRITE setAppSortOrder NOTIFY appSortOrderChanged)
    Q_PROPERTY(
        int appGridColumns READ appGridColumns WRITE setAppGridColumns NOTIFY appGridColumnsChanged)
    Q_PROPERTY(bool searchNativeApps READ searchNativeApps WRITE setSearchNativeApps NOTIFY
                   searchNativeAppsChanged)
    Q_PROPERTY(bool showNotificationBadges READ showNotificationBadges WRITE
                   setShowNotificationBadges NOTIFY showNotificationBadgesChanged)
    Q_PROPERTY(bool showFrequentApps READ showFrequentApps WRITE setShowFrequentApps NOTIFY
                   showFrequentAppsChanged)
    Q_PROPERTY(
        QVariantMap defaultApps READ defaultApps WRITE setDefaultApps NOTIFY defaultAppsChanged)

    // OOBE properties
    Q_PROPERTY(bool firstRunComplete READ firstRunComplete WRITE setFirstRunComplete NOTIFY
                   firstRunCompleteChanged)

    // Quick Settings customization
    Q_PROPERTY(QStringList enabledQuickSettingsTiles READ enabledQuickSettingsTiles WRITE
                   setEnabledQuickSettingsTiles NOTIFY enabledQuickSettingsTilesChanged)
    Q_PROPERTY(QStringList quickSettingsTileOrder READ quickSettingsTileOrder WRITE
                   setQuickSettingsTileOrder NOTIFY quickSettingsTileOrderChanged)

    // Keyboard settings
    Q_PROPERTY(bool keyboardAutoCorrection READ keyboardAutoCorrection WRITE
                   setKeyboardAutoCorrection NOTIFY keyboardAutoCorrectionChanged)
    Q_PROPERTY(bool keyboardPredictiveText READ keyboardPredictiveText WRITE
                   setKeyboardPredictiveText NOTIFY keyboardPredictiveTextChanged)
    Q_PROPERTY(bool keyboardWordFling READ keyboardWordFling WRITE setKeyboardWordFling NOTIFY
                   keyboardWordFlingChanged)
    Q_PROPERTY(bool keyboardPredictiveSpacing READ keyboardPredictiveSpacing WRITE
                   setKeyboardPredictiveSpacing NOTIFY keyboardPredictiveSpacingChanged)
    Q_PROPERTY(QString keyboardHapticStrength READ keyboardHapticStrength WRITE
                   setKeyboardHapticStrength NOTIFY keyboardHapticStrengthChanged)

  public:
    explicit SettingsManager(QObject *parent = nullptr);
    ~SettingsManager() override = default;

    // Existing getters
    qreal userScaleFactor() const {
        return m_userScaleFactor;
    }
    QString wallpaperPath() const {
        return m_wallpaperPath;
    }

    // Migrated getters
    QString deviceName() const {
        return m_deviceName;
    }
    bool autoLock() const {
        return m_autoLock;
    }
    int autoLockTimeout() const {
        return m_autoLockTimeout;
    }
    bool showNotificationPreviews() const {
        return m_showNotificationPreviews;
    }
    QString timeFormat() const {
        return m_timeFormat;
    }
    QString dateFormat() const {
        return m_dateFormat;
    }

    // Audio getters
    QString ringtone() const {
        return m_ringtone;
    }
    QString notificationSound() const {
        return m_notificationSound;
    }
    QString alarmSound() const {
        return m_alarmSound;
    }
    qreal mediaVolume() const {
        return m_mediaVolume;
    }
    qreal ringtoneVolume() const {
        return m_ringtoneVolume;
    }
    qreal alarmVolume() const {
        return m_alarmVolume;
    }
    qreal notificationVolume() const {
        return m_notificationVolume;
    }
    qreal systemVolume() const {
        return m_systemVolume;
    }

    // Display getters
    int screenTimeout() const {
        return m_screenTimeout;
    }
    bool autoBrightness() const {
        return m_autoBrightness;
    }
    QString statusBarClockPosition() const {
        return m_statusBarClockPosition;
    }

    // Notification getters
    bool showNotificationsOnLockScreen() const {
        return m_showNotificationsOnLockScreen;
    }

    // App management getters
    bool filterMobileFriendlyApps() const {
        return m_filterMobileFriendlyApps;
    }
    QStringList hiddenApps() const {
        return m_hiddenApps;
    }
    QString appSortOrder() const {
        return m_appSortOrder;
    }
    int appGridColumns() const {
        return m_appGridColumns;
    }
    bool searchNativeApps() const {
        return m_searchNativeApps;
    }
    bool showNotificationBadges() const {
        return m_showNotificationBadges;
    }
    bool showFrequentApps() const {
        return m_showFrequentApps;
    }
    QVariantMap defaultApps() const {
        return m_defaultApps;
    }

    // OOBE getters
    bool firstRunComplete() const {
        return m_firstRunComplete;
    }

    // Quick Settings getters
    QStringList enabledQuickSettingsTiles() const {
        return m_enabledQuickSettingsTiles;
    }
    QStringList quickSettingsTileOrder() const {
        return m_quickSettingsTileOrder;
    }

    // Keyboard getters
    bool keyboardAutoCorrection() const {
        return m_keyboardAutoCorrection;
    }
    bool keyboardPredictiveText() const {
        return m_keyboardPredictiveText;
    }
    bool keyboardWordFling() const {
        return m_keyboardWordFling;
    }
    bool keyboardPredictiveSpacing() const {
        return m_keyboardPredictiveSpacing;
    }
    QString keyboardHapticStrength() const {
        return m_keyboardHapticStrength;
    }

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
    void setMediaVolume(qreal volume);
    void setRingtoneVolume(qreal volume);
    void setAlarmVolume(qreal volume);
    void setNotificationVolume(qreal volume);
    void setSystemVolume(qreal volume);

    // Display setters
    void setScreenTimeout(int ms);
    void setAutoBrightness(bool enabled);
    void setStatusBarClockPosition(const QString &position);

    // Notification setters
    void setShowNotificationsOnLockScreen(bool enabled);

    // App management setters
    void setFilterMobileFriendlyApps(bool enabled);
    void setHiddenApps(const QStringList &apps);
    void setAppSortOrder(const QString &order);
    void setAppGridColumns(int columns);
    void setSearchNativeApps(bool enabled);
    void setShowNotificationBadges(bool enabled);
    void setShowFrequentApps(bool enabled);
    void setDefaultApps(const QVariantMap &apps);

    // OOBE setters
    void setFirstRunComplete(bool complete);

    // Quick Settings setters
    void setEnabledQuickSettingsTiles(const QStringList &tiles);
    void setQuickSettingsTileOrder(const QStringList &order);

    // Keyboard setters
    void setKeyboardAutoCorrection(bool enabled);
    void setKeyboardPredictiveText(bool enabled);
    void setKeyboardWordFling(bool enabled);
    void setKeyboardPredictiveSpacing(bool enabled);
    void setKeyboardHapticStrength(const QString &strength);

    // Invokable methods for sound lists
    Q_INVOKABLE QStringList availableRingtones();
    Q_INVOKABLE QStringList availableNotificationSounds();
    Q_INVOKABLE QStringList availableAlarmSounds();
    Q_INVOKABLE QStringList screenTimeoutOptions();
    Q_INVOKABLE int         screenTimeoutValue(const QString &option);
    Q_INVOKABLE QString     formatSoundName(const QString &path);

    // Existing invokables
    Q_INVOKABLE QVariant get(const QString &key, const QVariant &defaultValue = QVariant());
    Q_INVOKABLE void     set(const QString &key, const QVariant &value);
    Q_INVOKABLE void     sync();

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
    void mediaVolumeChanged();
    void ringtoneVolumeChanged();
    void alarmVolumeChanged();
    void notificationVolumeChanged();
    void systemVolumeChanged();

    // Display signals
    void screenTimeoutChanged();
    void autoBrightnessChanged();
    void statusBarClockPositionChanged();

    // Notification signals
    void showNotificationsOnLockScreenChanged();

    // App management signals
    void filterMobileFriendlyAppsChanged();
    void hiddenAppsChanged();
    void appSortOrderChanged();
    void appGridColumnsChanged();
    void searchNativeAppsChanged();
    void showNotificationBadgesChanged();
    void showFrequentAppsChanged();
    void defaultAppsChanged();

    // OOBE signals
    void firstRunCompleteChanged();

    // Quick Settings signals
    void enabledQuickSettingsTilesChanged();
    void quickSettingsTileOrderChanged();

    // Keyboard signals
    void keyboardAutoCorrectionChanged();
    void keyboardPredictiveTextChanged();
    void keyboardWordFlingChanged();
    void keyboardPredictiveSpacingChanged();
    void keyboardHapticStrengthChanged();

  private:
    void      load();
    void      save();

    QSettings m_settings;

    // Existing members
    qreal   m_userScaleFactor;
    QString m_wallpaperPath;

    // Migrated members
    QString m_deviceName;
    bool    m_autoLock;
    int     m_autoLockTimeout;
    bool    m_showNotificationPreviews;
    QString m_timeFormat;
    QString m_dateFormat;

    // Audio members
    QString m_ringtone;
    QString m_notificationSound;
    QString m_alarmSound;
    qreal   m_mediaVolume;
    qreal   m_ringtoneVolume;
    qreal   m_alarmVolume;
    qreal   m_notificationVolume;
    qreal   m_systemVolume;

    // Display members
    int     m_screenTimeout;
    bool    m_autoBrightness;
    QString m_statusBarClockPosition;

    // Notification members
    bool m_showNotificationsOnLockScreen;

    // App management members
    bool        m_filterMobileFriendlyApps;
    QStringList m_hiddenApps;
    QString     m_appSortOrder;
    int         m_appGridColumns;
    bool        m_searchNativeApps;
    bool        m_showNotificationBadges;
    bool        m_showFrequentApps;
    QVariantMap m_defaultApps;

    // OOBE members
    bool m_firstRunComplete;

    // Quick Settings members
    QStringList m_enabledQuickSettingsTiles;
    QStringList m_quickSettingsTileOrder;

    // Keyboard members
    bool    m_keyboardAutoCorrection;
    bool    m_keyboardPredictiveText;
    bool    m_keyboardWordFling;
    bool    m_keyboardPredictiveSpacing;
    QString m_keyboardHapticStrength;
};
