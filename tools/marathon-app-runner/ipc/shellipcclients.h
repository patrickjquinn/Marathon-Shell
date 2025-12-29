#pragma once

#include <QObject>
#include <QAbstractListModel>
#include <QDBusInterface>
#include <QDBusVariant>
#include <QElapsedTimer>
#include <QVariantList>
#include <QVariantMap>

class PermissionClient : public QObject {
    Q_OBJECT

  public:
    explicit PermissionClient(QObject *parent = nullptr);

    Q_INVOKABLE bool hasPermission(const QString &appId, const QString &permission);
    Q_INVOKABLE void requestPermission(const QString &appId, const QString &permission);
    Q_INVOKABLE void setPermission(const QString &appId, const QString &permission, bool granted,
                                   bool remember = true);

  signals:
    void permissionGranted(const QString &appId, const QString &permission);
    void permissionDenied(const QString &appId, const QString &permission);
    void permissionRequested(const QString &appId, const QString &permission);

  private:
    QDBusInterface m_iface;
};

class ContactsClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList contacts READ contacts NOTIFY contactsChanged)
    Q_PROPERTY(int count READ count NOTIFY contactsChanged)

  public:
    explicit ContactsClient(QObject *parent = nullptr);

    QVariantList contacts() const {
        return m_contacts;
    }
    int count() const {
        return static_cast<int>(m_contacts.size());
    }

    Q_INVOKABLE void         refresh();
    Q_INVOKABLE void         addContact(const QString &name, const QString &phone,
                                        const QString &email = QString());
    Q_INVOKABLE void         updateContact(int id, const QVariantMap &data);
    Q_INVOKABLE void         deleteContact(int id);
    Q_INVOKABLE QVariantList searchContacts(const QString &query);
    Q_INVOKABLE QVariantMap  getContact(int id);
    Q_INVOKABLE QVariantMap  getContactByNumber(const QString &phoneNumber);

  signals:
    void contactsChanged();
    void contactAdded(int id);
    void contactUpdated(int id);
    void contactDeleted(int id);

  private:
    void           setContacts(const QVariantList &v);
    QDBusInterface m_iface;
    QVariantList   m_contacts;
};

class CallHistoryClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int count READ count NOTIFY historyChanged)

  public:
    explicit CallHistoryClient(QObject *parent = nullptr);

    QVariantList history() const {
        return m_history;
    }
    int count() const {
        return static_cast<int>(m_history.size());
    }

    Q_INVOKABLE void         refresh();
    Q_INVOKABLE void         addCall(const QString &number, const QString &type, qint64 timestamp,
                                     int duration);
    Q_INVOKABLE void         deleteCall(int id);
    Q_INVOKABLE void         clearHistory();
    Q_INVOKABLE QVariantMap  getCallById(int id);
    Q_INVOKABLE QVariantList getCallsByNumber(const QString &number);

  signals:
    void historyChanged();
    void callAdded(int id);

  private:
    void           setHistory(const QVariantList &v);
    QDBusInterface m_iface;
    QVariantList   m_history;
};

class TelephonyClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString callState READ callState NOTIFY callStateChanged)
    Q_PROPERTY(bool hasModem READ hasModem NOTIFY modemChanged)
    Q_PROPERTY(QString activeNumber READ activeNumber NOTIFY activeNumberChanged)

  public:
    explicit TelephonyClient(QObject *parent = nullptr);

    QString callState() const {
        return m_callState;
    }
    bool hasModem() const {
        return m_hasModem;
    }
    QString activeNumber() const {
        return m_activeNumber;
    }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void dial(const QString &number);
    Q_INVOKABLE void answer();
    Q_INVOKABLE void hangup();
    Q_INVOKABLE void sendDTMF(const QString &digit);

  signals:
    void callStateChanged(const QString &state);
    void incomingCall(const QString &number);
    void callFailed(const QString &reason);
    void modemChanged(bool hasModem);
    void activeNumberChanged(const QString &number);

  private slots:
    void setCallState(const QString &s);
    void setHasModem(bool b);
    void setActiveNumber(const QString &n);

  private:
    QDBusInterface m_iface;
    QString        m_callState;
    bool           m_hasModem = false;
    QString        m_activeNumber;
};

class SmsClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList conversations READ conversations NOTIFY conversationsChanged)

  public:
    explicit SmsClient(QObject *parent = nullptr);

    QVariantList conversations() const {
        return m_conversations;
    }

    Q_INVOKABLE void         refresh();
    Q_INVOKABLE void         sendMessage(const QString &recipient, const QString &text);
    Q_INVOKABLE QVariantList getMessages(const QString &conversationId);
    Q_INVOKABLE void         deleteConversation(const QString &conversationId);
    Q_INVOKABLE void         markAsRead(const QString &conversationId);
    Q_INVOKABLE QString      generateConversationId(const QString &number);

  signals:
    void messageReceived(const QString &sender, const QString &text, qint64 timestamp);
    void messageSent(const QString &recipient, qint64 timestamp);
    void sendFailed(const QString &recipient, const QString &reason);
    void conversationsChanged();

  private:
    void           setConversations(const QVariantList &v);
    QDBusInterface m_iface;
    QVariantList   m_conversations;
};

class MediaLibraryClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int photoCount READ photoCount NOTIFY libraryChanged)
    Q_PROPERTY(int videoCount READ videoCount NOTIFY libraryChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)

  public:
    explicit MediaLibraryClient(const QString &appId, QObject *parent = nullptr);

    QVariantList albums() const {
        return m_albums;
    }
    bool isScanning() const {
        return m_isScanning;
    }
    int photoCount() const {
        return m_photoCount;
    }
    int videoCount() const {
        return m_videoCount;
    }
    int scanProgress() const {
        return m_scanProgress;
    }

    Q_INVOKABLE void         refresh();
    Q_INVOKABLE void         scanLibrary();
    Q_INVOKABLE void         scanLibraryAsync();
    Q_INVOKABLE QVariantList getPhotos(const QString &albumId);
    Q_INVOKABLE QVariantList getAllPhotos();
    Q_INVOKABLE QVariantList getVideos();
    Q_INVOKABLE QString      generateThumbnail(const QString &filePath);
    Q_INVOKABLE void         deleteMedia(int mediaId);

  signals:
    void albumsChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int photoCount, int videoCount);
    void newMediaAdded(const QString &path);
    void libraryChanged();
    void scanProgressChanged(int progress);

  private slots:
    void setScanning(bool scanning);
    void setScanProgress(int progress);
    void onLibraryChanged();

  private:
    bool           ensureStoragePermission();
    void           setAlbums(const QVariantList &v);

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;

    QVariantList   m_albums;
    bool           m_isScanning   = false;
    int            m_photoCount   = 0;
    int            m_videoCount   = 0;
    int            m_scanProgress = 0;
};

class SettingsClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(qreal userScaleFactor READ userScaleFactor WRITE setUserScaleFactor NOTIFY
                   userScaleFactorChanged)
    Q_PROPERTY(
        QString wallpaperPath READ wallpaperPath WRITE setWallpaperPath NOTIFY wallpaperPathChanged)
    Q_PROPERTY(QString deviceName READ deviceName WRITE setDeviceName NOTIFY deviceNameChanged)
    Q_PROPERTY(bool autoLock READ autoLock WRITE setAutoLock NOTIFY autoLockChanged)
    Q_PROPERTY(int autoLockTimeout READ autoLockTimeout WRITE setAutoLockTimeout NOTIFY
                   autoLockTimeoutChanged)
    Q_PROPERTY(bool showNotificationPreviews READ showNotificationPreviews WRITE
                   setShowNotificationPreviews NOTIFY showNotificationPreviewsChanged)
    Q_PROPERTY(QString timeFormat READ timeFormat WRITE setTimeFormat NOTIFY timeFormatChanged)
    Q_PROPERTY(QString dateFormat READ dateFormat WRITE setDateFormat NOTIFY dateFormatChanged)

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
    Q_PROPERTY(bool dndEnabled READ dndEnabled WRITE setDndEnabled NOTIFY dndEnabledChanged)
    Q_PROPERTY(bool vibrationEnabled READ vibrationEnabled WRITE setVibrationEnabled NOTIFY
                   vibrationEnabledChanged)
    Q_PROPERTY(
        QString audioProfile READ audioProfile WRITE setAudioProfile NOTIFY audioProfileChanged)

    Q_PROPERTY(
        int screenTimeout READ screenTimeout WRITE setScreenTimeout NOTIFY screenTimeoutChanged)
    Q_PROPERTY(bool autoBrightness READ autoBrightness WRITE setAutoBrightness NOTIFY
                   autoBrightnessChanged)
    Q_PROPERTY(QString statusBarClockPosition READ statusBarClockPosition WRITE
                   setStatusBarClockPosition NOTIFY statusBarClockPositionChanged)

    Q_PROPERTY(bool showNotificationsOnLockScreen READ showNotificationsOnLockScreen WRITE
                   setShowNotificationsOnLockScreen NOTIFY showNotificationsOnLockScreenChanged)

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

    Q_PROPERTY(bool firstRunComplete READ firstRunComplete WRITE setFirstRunComplete NOTIFY
                   firstRunCompleteChanged)

    Q_PROPERTY(QStringList enabledQuickSettingsTiles READ enabledQuickSettingsTiles WRITE
                   setEnabledQuickSettingsTiles NOTIFY enabledQuickSettingsTilesChanged)
    Q_PROPERTY(QStringList quickSettingsTileOrder READ quickSettingsTileOrder WRITE
                   setQuickSettingsTileOrder NOTIFY quickSettingsTileOrderChanged)

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
    explicit SettingsClient(const QString &appId, QObject *parent = nullptr);

    qreal                   userScaleFactor() const;
    QString                 wallpaperPath() const;
    QString                 deviceName() const;
    bool                    autoLock() const;
    int                     autoLockTimeout() const;
    bool                    showNotificationPreviews() const;
    QString                 timeFormat() const;
    QString                 dateFormat() const;

    QString                 ringtone() const;
    QString                 notificationSound() const;
    QString                 alarmSound() const;
    qreal                   mediaVolume() const;
    qreal                   ringtoneVolume() const;
    qreal                   alarmVolume() const;
    qreal                   notificationVolume() const;
    qreal                   systemVolume() const;
    bool                    dndEnabled() const;
    bool                    vibrationEnabled() const;
    QString                 audioProfile() const;

    int                     screenTimeout() const;
    bool                    autoBrightness() const;
    QString                 statusBarClockPosition() const;

    bool                    showNotificationsOnLockScreen() const;

    bool                    filterMobileFriendlyApps() const;
    QStringList             hiddenApps() const;
    QString                 appSortOrder() const;
    int                     appGridColumns() const;
    bool                    searchNativeApps() const;
    bool                    showNotificationBadges() const;
    bool                    showFrequentApps() const;
    QVariantMap             defaultApps() const;

    bool                    firstRunComplete() const;

    QStringList             enabledQuickSettingsTiles() const;
    QStringList             quickSettingsTileOrder() const;

    bool                    keyboardAutoCorrection() const;
    bool                    keyboardPredictiveText() const;
    bool                    keyboardWordFling() const;
    bool                    keyboardPredictiveSpacing() const;
    QString                 keyboardHapticStrength() const;

    void                    setUserScaleFactor(qreal v);
    void                    setWallpaperPath(const QString &v);
    void                    setDeviceName(const QString &v);
    void                    setAutoLock(bool v);
    void                    setAutoLockTimeout(int v);
    void                    setShowNotificationPreviews(bool v);
    void                    setTimeFormat(const QString &v);
    void                    setDateFormat(const QString &v);

    void                    setRingtone(const QString &v);
    void                    setNotificationSound(const QString &v);
    void                    setAlarmSound(const QString &v);
    void                    setMediaVolume(qreal v);
    void                    setRingtoneVolume(qreal v);
    void                    setAlarmVolume(qreal v);
    void                    setNotificationVolume(qreal v);
    void                    setSystemVolume(qreal v);
    void                    setDndEnabled(bool v);
    void                    setVibrationEnabled(bool v);
    void                    setAudioProfile(const QString &v);

    void                    setScreenTimeout(int v);
    void                    setAutoBrightness(bool v);
    void                    setStatusBarClockPosition(const QString &v);

    void                    setShowNotificationsOnLockScreen(bool v);

    void                    setFilterMobileFriendlyApps(bool v);
    void                    setHiddenApps(const QStringList &v);
    void                    setAppSortOrder(const QString &v);
    void                    setAppGridColumns(int v);
    void                    setSearchNativeApps(bool v);
    void                    setShowNotificationBadges(bool v);
    void                    setShowFrequentApps(bool v);
    void                    setDefaultApps(const QVariantMap &v);

    void                    setFirstRunComplete(bool v);

    void                    setEnabledQuickSettingsTiles(const QStringList &v);
    void                    setQuickSettingsTileOrder(const QStringList &v);

    void                    setKeyboardAutoCorrection(bool v);
    void                    setKeyboardPredictiveText(bool v);
    void                    setKeyboardWordFling(bool v);
    void                    setKeyboardPredictiveSpacing(bool v);
    void                    setKeyboardHapticStrength(const QString &v);

    Q_INVOKABLE QStringList availableRingtones();
    Q_INVOKABLE QStringList availableNotificationSounds();
    Q_INVOKABLE QStringList availableAlarmSounds();
    Q_INVOKABLE QStringList screenTimeoutOptions();
    Q_INVOKABLE int         screenTimeoutValue(const QString &option);
    Q_INVOKABLE QString     formatSoundName(const QString &path);
    Q_INVOKABLE QString     assetUrl(const QString &relativePath);
    Q_INVOKABLE QVariant    get(const QString &key, const QVariant &defaultValue = QVariant());
    Q_INVOKABLE void        set(const QString &key, const QVariant &value);
    Q_INVOKABLE void        sync();

  signals:
    void userScaleFactorChanged();
    void wallpaperPathChanged();
    void deviceNameChanged();
    void autoLockChanged();
    void autoLockTimeoutChanged();
    void showNotificationPreviewsChanged();
    void timeFormatChanged();
    void dateFormatChanged();

    void ringtoneChanged();
    void notificationSoundChanged();
    void alarmSoundChanged();
    void mediaVolumeChanged();
    void ringtoneVolumeChanged();
    void alarmVolumeChanged();
    void notificationVolumeChanged();
    void systemVolumeChanged();
    void dndEnabledChanged();
    void vibrationEnabledChanged();
    void audioProfileChanged();

    void screenTimeoutChanged();
    void autoBrightnessChanged();
    void statusBarClockPositionChanged();

    void showNotificationsOnLockScreenChanged();

    void filterMobileFriendlyAppsChanged();
    void hiddenAppsChanged();
    void appSortOrderChanged();
    void appGridColumnsChanged();
    void searchNativeAppsChanged();
    void showNotificationBadgesChanged();
    void showFrequentAppsChanged();
    void defaultAppsChanged();

    void firstRunCompleteChanged();

    void enabledQuickSettingsTilesChanged();
    void quickSettingsTileOrderChanged();

    void keyboardAutoCorrectionChanged();
    void keyboardPredictiveTextChanged();
    void keyboardWordFlingChanged();
    void keyboardPredictiveSpacingChanged();
    void keyboardHapticStrengthChanged();

  private slots:
    void onPropertyChanged(const QString &name, const QDBusVariant &value);

  private:
    bool           ensureSystemPermission();
    bool           ensureStoragePermission();
    bool           ensurePermissionForKey(const QString &key);
    bool           isAppScopedKey(const QString &key) const;
    void           refresh();
    void           setProp(const QString &name, const QVariant &value);
    QVariant       prop(const QString &name, const QVariant &fallback = QVariant()) const;

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
    bool           m_storageRequested    = false;
};

class BluetoothClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY stateChanged)
    Q_PROPERTY(QString adapterName READ adapterName NOTIFY stateChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY stateChanged)
    Q_PROPERTY(QVariantList pairedDevices READ pairedDevices NOTIFY stateChanged)

  public:
    explicit BluetoothClient(const QString &appId, QObject *parent = nullptr);

    bool             available() const;
    bool             enabled() const;
    void             setEnabled(bool enabled);
    bool             scanning() const;
    QString          adapterName() const;
    QVariantList     devices() const;
    QVariantList     pairedDevices() const;

    Q_INVOKABLE void startScan();
    Q_INVOKABLE void stopScan();
    Q_INVOKABLE void pairDevice(const QString &address, const QString &pin = QString());
    Q_INVOKABLE void unpairDevice(const QString &address);
    Q_INVOKABLE void connectDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice(const QString &address);
    Q_INVOKABLE void confirmPairing(const QString &address, bool confirmed);
    Q_INVOKABLE void cancelPairing(const QString &address);

  signals:
    void stateChanged();
    void pairingFailed(const QString &address, const QString &error);
    void pairingSucceeded(const QString &address);
    void pinRequested(const QString &address, const QString &deviceName);
    void passkeyRequested(const QString &address, const QString &deviceName);
    void passkeyConfirmation(const QString &address, const QString &deviceName, quint32 passkey);

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool           ensureSystemPermission();
    void           refresh();

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    int            m_refreshRetryCount = 0;
    QElapsedTimer  m_startTimer;
    bool           m_loggedFirstSync     = false;
    bool           m_loggedFirstFailure  = false;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
};

class DisplayClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(bool autoBrightnessEnabled READ autoBrightnessEnabled WRITE setAutoBrightnessEnabled
                   NOTIFY stateChanged)
    Q_PROPERTY(bool rotationLocked READ rotationLocked WRITE setRotationLocked NOTIFY stateChanged)
    Q_PROPERTY(int screenTimeout READ screenTimeout WRITE setScreenTimeout NOTIFY stateChanged)
    Q_PROPERTY(QString screenTimeoutString READ screenTimeoutString NOTIFY stateChanged)
    Q_PROPERTY(double brightness READ brightness WRITE setBrightness NOTIFY stateChanged)
    Q_PROPERTY(bool nightLightEnabled READ nightLightEnabled WRITE setNightLightEnabled NOTIFY
                   stateChanged)
    Q_PROPERTY(int nightLightTemperature READ nightLightTemperature WRITE setNightLightTemperature
                   NOTIFY stateChanged)
    Q_PROPERTY(QString nightLightSchedule READ nightLightSchedule WRITE setNightLightSchedule NOTIFY
                   stateChanged)

  public:
    explicit DisplayClient(const QString &appId, QObject *parent = nullptr);

    bool             available() const;
    bool             autoBrightnessEnabled() const;
    void             setAutoBrightnessEnabled(bool enabled);
    bool             rotationLocked() const;
    void             setRotationLocked(bool locked);
    int              screenTimeout() const;
    void             setScreenTimeout(int seconds);
    QString          screenTimeoutString() const;
    double           brightness() const;
    void             setBrightness(double v);
    bool             nightLightEnabled() const;
    void             setNightLightEnabled(bool enabled);
    int              nightLightTemperature() const;
    void             setNightLightTemperature(int t);
    QString          nightLightSchedule() const;
    void             setNightLightSchedule(const QString &s);

    Q_INVOKABLE void setScreenState(bool on);

  signals:
    void stateChanged();

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool           ensureSystemPermission();
    void           refresh();

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    int            m_refreshRetryCount = 0;
    QElapsedTimer  m_startTimer;
    bool           m_loggedFirstSync     = false;
    bool           m_loggedFirstFailure  = false;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
};

class RemoteAudioStreamModel : public QAbstractListModel {
    Q_OBJECT

  public:
    enum StreamRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        AppNameRole,
        VolumeRole,
        MutedRole,
        MediaClassRole
    };

    explicit RemoteAudioStreamModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void                   setStreams(const QVariantList &streams);

  private:
    QVariantList m_streams;
};

class AudioClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(double volume READ volume NOTIFY stateChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY stateChanged)
    Q_PROPERTY(bool perAppVolumeSupported READ perAppVolumeSupported NOTIFY stateChanged)
    Q_PROPERTY(RemoteAudioStreamModel *streams READ streams CONSTANT)

  public:
    explicit AudioClient(const QString &appId, QObject *parent = nullptr);

    bool                    available() const;
    double                  volume() const;
    bool                    muted() const;
    bool                    perAppVolumeSupported() const;
    RemoteAudioStreamModel *streams() {
        return m_streamModel;
    }

    Q_INVOKABLE void setVolume(double v);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void setStreamVolume(int streamId, double volume);
    Q_INVOKABLE void setStreamMuted(int streamId, bool muted);
    Q_INVOKABLE void refreshStreams();
    Q_INVOKABLE void setDoNotDisturb(bool enabled);
    Q_INVOKABLE void setAudioProfile(const QString &profile);
    Q_INVOKABLE void playRingtone();
    Q_INVOKABLE void stopRingtone();
    Q_INVOKABLE void playNotificationSound();
    Q_INVOKABLE void playAlarmSound();
    Q_INVOKABLE void stopAlarmSound();
    Q_INVOKABLE void previewSound(const QString &soundPath);
    Q_INVOKABLE void vibratePattern(const QVariantList &pattern);

  signals:
    void stateChanged();

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool                    ensureSystemPermission();
    void                    refresh();
    QVariant                v(const QString &k, const QVariant &fallback = QVariant()) const;

    QString                 m_appId;
    QDBusInterface          m_iface;
    QDBusInterface          m_permIface;
    QVariantMap             m_state;
    RemoteAudioStreamModel *m_streamModel       = nullptr;
    int                     m_refreshRetryCount = 0;
    QElapsedTimer           m_startTimer;
    bool                    m_loggedFirstSync     = false;
    bool                    m_loggedFirstFailure  = false;
    bool                    m_refreshInFlight     = false;
    bool                    m_permissionRequested = false;
};

class PowerClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY stateChanged)
    Q_PROPERTY(bool isCharging READ isCharging NOTIFY stateChanged)
    Q_PROPERTY(bool isPluggedIn READ isPluggedIn NOTIFY stateChanged)
    Q_PROPERTY(bool isPowerSaveMode READ isPowerSaveMode NOTIFY stateChanged)
    Q_PROPERTY(int estimatedBatteryTime READ estimatedBatteryTime NOTIFY stateChanged)
    Q_PROPERTY(QString powerProfile READ powerProfile NOTIFY stateChanged)
    Q_PROPERTY(bool powerProfilesSupported READ powerProfilesSupported NOTIFY stateChanged)

  public:
    explicit PowerClient(const QString &appId, QObject *parent = nullptr);

    int              batteryLevel() const;
    bool             isCharging() const;
    bool             isPluggedIn() const;
    bool             isPowerSaveMode() const;
    int              estimatedBatteryTime() const;
    QString          powerProfile() const;
    bool             powerProfilesSupported() const;

    Q_INVOKABLE void setPowerSaveMode(bool enabled);
    Q_INVOKABLE void setPowerProfile(const QString &profile);
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void shutdown();

  signals:
    void stateChanged();

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool           ensureSystemPermission();
    void           refresh();
    QVariant       v(const QString &k, const QVariant &fallback = QVariant()) const;

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    int            m_refreshRetryCount = 0;
    QElapsedTimer  m_startTimer;
    bool           m_loggedFirstSync     = false;
    bool           m_loggedFirstFailure  = false;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
};

class NetworkClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool wifiConnected READ wifiConnected NOTIFY wifiConnectedChanged)
    Q_PROPERTY(QString wifiSsid READ wifiSsid NOTIFY wifiSsidChanged)
    Q_PROPERTY(int wifiSignalStrength READ wifiSignalStrength NOTIFY wifiSignalStrengthChanged)
    Q_PROPERTY(bool ethernetConnected READ ethernetConnected NOTIFY ethernetConnectedChanged)
    Q_PROPERTY(QString ethernetConnectionName READ ethernetConnectionName NOTIFY
                   ethernetConnectionNameChanged)
    Q_PROPERTY(bool wifiAvailable READ wifiAvailable NOTIFY wifiAvailableChanged)
    Q_PROPERTY(bool bluetoothAvailable READ bluetoothAvailable NOTIFY bluetoothAvailableChanged)
    Q_PROPERTY(bool hotspotSupported READ hotspotSupported NOTIFY hotspotSupportedChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled NOTIFY bluetoothEnabledChanged)
    Q_PROPERTY(bool airplaneModeEnabled READ airplaneModeEnabled NOTIFY airplaneModeEnabledChanged)
    Q_PROPERTY(
        QVariantList availableNetworks READ availableNetworks NOTIFY availableNetworksChanged)

  public:
    explicit NetworkClient(const QString &appId, QObject *parent = nullptr);

    bool             wifiEnabled() const;
    bool             wifiConnected() const;
    QString          wifiSsid() const;
    int              wifiSignalStrength() const;
    bool             ethernetConnected() const;
    QString          ethernetConnectionName() const;
    bool             wifiAvailable() const;
    bool             bluetoothAvailable() const;
    bool             hotspotSupported() const;
    bool             bluetoothEnabled() const;
    bool             airplaneModeEnabled() const;
    QVariantList     availableNetworks() const;

    Q_INVOKABLE void enableWifi();
    Q_INVOKABLE void disableWifi();
    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectToNetwork(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectWifi();
    Q_INVOKABLE void setAirplaneMode(bool enabled);
    Q_INVOKABLE void createHotspot(const QString &ssid, const QString &password);
    Q_INVOKABLE void stopHotspot();
    Q_INVOKABLE bool isHotspotActive();

  signals:
    void wifiEnabledChanged();
    void wifiConnectedChanged();
    void wifiSsidChanged();
    void wifiSignalStrengthChanged();
    void ethernetConnectedChanged();
    void ethernetConnectionNameChanged();
    void wifiAvailableChanged();
    void bluetoothAvailableChanged();
    void hotspotSupportedChanged();
    void bluetoothEnabledChanged();
    void airplaneModeEnabledChanged();
    void availableNetworksChanged();

    void networkError(const QString &message);
    void connectionSuccess();
    void connectionFailed(const QString &message);

  private slots:
    void onStateChanged(const QVariantMap &state);

  private:
    bool           ensureNetworkPermission();
    void           refresh();
    QVariant       v(const QString &k, const QVariant &fallback = QVariant()) const;

    QString        m_appId;
    QDBusInterface m_iface;
    QDBusInterface m_permIface;
    QVariantMap    m_state;
    int            m_refreshRetryCount = 0;
    QElapsedTimer  m_startTimer;
    bool           m_loggedFirstSync     = false;
    bool           m_loggedFirstFailure  = false;
    bool           m_refreshInFlight     = false;
    bool           m_permissionRequested = false;
};

class NavigationClient : public QObject {
    Q_OBJECT

  public:
    explicit NavigationClient(QObject *parent = nullptr);

    Q_INVOKABLE bool launchApp(const QString &appId);
    Q_INVOKABLE bool navigate(const QString &uri);
    Q_INVOKABLE bool launchAppWithRoute(const QString &appId, const QString &route,
                                        const QString &paramsJson = QString());

  signals:
    void appLaunched(const QString &appId);
    void navigationFailed(const QString &uri, const QString &error);

  private:
    QDBusInterface m_iface;
};
