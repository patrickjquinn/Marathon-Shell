#include "shellservices.h"

#include "../applaunchservice.h"
#include "../marathonpermissionmanager.h"
#include "../settingsmanager.h"
#include "../bluetoothmanager.h"
#include "../displaymanagercpp.h"
#include "../networkmanagercpp.h"
#include "../powermanagercpp.h"
#include "../audiomanagercpp.h"
#include "../audiopolicycontroller.h"

#include "callhistorymanager.h"
#include "contactsmanager.h"
#include "smsservice.h"
#include "telephonyservice.h"
#include "medialibrarymanager.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QCoreApplication>
#include <QFile>

static bool hasAnyPermission(MarathonPermissionManager *pm, const QString &appId,
                             const QStringList &perms) {
    if (!pm)
        return false;
    for (const auto &p : perms) {
        if (pm->hasPermission(appId, p))
            return true;
    }
    return false;
}

static QString dbusCallerAppIdOrEmpty(const QDBusContext &ctx, AppLaunchService *als) {
    if (!ctx.calledFromDBus() || !als)
        return {};
    const QString sender   = ctx.message().service();
    auto          pidReply = ctx.connection().interface()->servicePid(sender);
    if (!pidReply.isValid())
        return {};
    const qint64  pid = static_cast<qint64>(pidReply.value());

    const QString mapped = als->appIdForPid(pid);
    if (!mapped.isEmpty())
        return mapped;

    // Race-proofing for strict IPC:
    // marathon-app-runner can legitimately call into the shell over DBus before we observed
    // its pid via compositor signals. If (and only if) the caller is a direct child of this shell
    // and looks like marathon-app-runner with a --app-id, we can safely self-heal the map.
    const qint64 shellPid = static_cast<qint64>(QCoreApplication::applicationPid());
    if (shellPid <= 0 || pid <= 0)
        return {};

    QFile statFile(QStringLiteral("/proc/%1/stat").arg(pid));
    if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    const QByteArray statLine = statFile.readAll();
    const qsizetype  closeIdx = statLine.lastIndexOf(')');
    if (closeIdx < 0)
        return {};
    const QByteArray        after = statLine.mid(closeIdx + 1).trimmed(); // "S <ppid> ..."
    const QList<QByteArray> parts = after.split(' ');
    if (parts.size() < 2)
        return {};
    const qint64 ppid = parts.at(1).toLongLong();
    if (ppid != shellPid)
        return {};

    QFile cmdFile(QStringLiteral("/proc/%1/cmdline").arg(pid));
    if (!cmdFile.open(QIODevice::ReadOnly))
        return {};
    const QByteArray        cmdRaw = cmdFile.readAll();
    const QList<QByteArray> argv   = cmdRaw.split('\0');
    if (argv.isEmpty())
        return {};

    const QString argv0 = QString::fromLocal8Bit(argv.value(0));
    if (!argv0.contains("marathon-app-runner"))
        return {};

    QString appId;
    for (int i = 0; i + 1 < argv.size(); ++i) {
        if (argv[i] == "--app-id") {
            appId = QString::fromLocal8Bit(argv[i + 1]);
            break;
        }
    }
    if (appId.isEmpty())
        return {};
    if (!als->isMarathonAppId(appId))
        return {};

    als->registerPidForAppId(pid, appId);
    return appId;
}

// ---- SettingsObject ----

SettingsObject::SettingsObject(SettingsManager *settings, MarathonPermissionManager *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_settings);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto emitProp = [this](const char *name, const QVariant &v) {
        emit PropertyChanged(QString::fromLatin1(name), QDBusVariant(v));
    };

    QObject::connect(
        m_settings, &SettingsManager::userScaleFactorChanged, this,
        [this, emitProp]() { emitProp("userScaleFactor", m_settings->userScaleFactor()); });
    QObject::connect(m_settings, &SettingsManager::wallpaperPathChanged, this, [this, emitProp]() {
        emitProp("wallpaperPath", m_settings->wallpaperPath());
    });
    QObject::connect(m_settings, &SettingsManager::deviceNameChanged, this,
                     [this, emitProp]() { emitProp("deviceName", m_settings->deviceName()); });
    QObject::connect(m_settings, &SettingsManager::timeFormatChanged, this,
                     [this, emitProp]() { emitProp("timeFormat", m_settings->timeFormat()); });
    QObject::connect(m_settings, &SettingsManager::dateFormatChanged, this,
                     [this, emitProp]() { emitProp("dateFormat", m_settings->dateFormat()); });
    QObject::connect(m_settings, &SettingsManager::screenTimeoutChanged, this, [this, emitProp]() {
        emitProp("screenTimeout", m_settings->screenTimeout());
    });
    QObject::connect(m_settings, &SettingsManager::statusBarClockPositionChanged, this,
                     [this, emitProp]() {
                         emitProp("statusBarClockPosition", m_settings->statusBarClockPosition());
                     });
    QObject::connect(
        m_settings, &SettingsManager::filterMobileFriendlyAppsChanged, this, [this, emitProp]() {
            emitProp("filterMobileFriendlyApps", m_settings->filterMobileFriendlyApps());
        });
    QObject::connect(m_settings, &SettingsManager::hiddenAppsChanged, this,
                     [this, emitProp]() { emitProp("hiddenApps", m_settings->hiddenApps()); });
    QObject::connect(m_settings, &SettingsManager::appSortOrderChanged, this,
                     [this, emitProp]() { emitProp("appSortOrder", m_settings->appSortOrder()); });
    QObject::connect(m_settings, &SettingsManager::appGridColumnsChanged, this, [this, emitProp]() {
        emitProp("appGridColumns", m_settings->appGridColumns());
    });
    QObject::connect(
        m_settings, &SettingsManager::searchNativeAppsChanged, this,
        [this, emitProp]() { emitProp("searchNativeApps", m_settings->searchNativeApps()); });
    QObject::connect(m_settings, &SettingsManager::showNotificationBadgesChanged, this,
                     [this, emitProp]() {
                         emitProp("showNotificationBadges", m_settings->showNotificationBadges());
                     });
    QObject::connect(
        m_settings, &SettingsManager::showFrequentAppsChanged, this,
        [this, emitProp]() { emitProp("showFrequentApps", m_settings->showFrequentApps()); });
    QObject::connect(m_settings, &SettingsManager::defaultAppsChanged, this,
                     [this, emitProp]() { emitProp("defaultApps", m_settings->defaultApps()); });
    QObject::connect(
        m_settings, &SettingsManager::enabledQuickSettingsTilesChanged, this, [this, emitProp]() {
            emitProp("enabledQuickSettingsTiles", m_settings->enabledQuickSettingsTiles());
        });
    QObject::connect(m_settings, &SettingsManager::quickSettingsTileOrderChanged, this,
                     [this, emitProp]() {
                         emitProp("quickSettingsTileOrder", m_settings->quickSettingsTileOrder());
                     });
}

QString SettingsObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool SettingsObject::requireSystem() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"system"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: system");
        return false;
    }
    return true;
}

bool SettingsObject::requireStorage() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"storage"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: storage");
        return false;
    }
    return true;
}

bool SettingsObject::isAppScopedKey(const QString &key) const {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty())
        return false;
    return key.startsWith(caller + "/");
}

QVariantMap SettingsObject::GetState() {
    if (!requireSystem())
        return {};

    return {
        {"userScaleFactor", m_settings->userScaleFactor()},
        {"wallpaperPath", m_settings->wallpaperPath()},
        {"deviceName", m_settings->deviceName()},
        {"autoLock", m_settings->autoLock()},
        {"autoLockTimeout", m_settings->autoLockTimeout()},
        {"showNotificationPreviews", m_settings->showNotificationPreviews()},
        {"timeFormat", m_settings->timeFormat()},
        {"dateFormat", m_settings->dateFormat()},
        {"ringtone", m_settings->ringtone()},
        {"notificationSound", m_settings->notificationSound()},
        {"alarmSound", m_settings->alarmSound()},
        {"mediaVolume", m_settings->mediaVolume()},
        {"ringtoneVolume", m_settings->ringtoneVolume()},
        {"alarmVolume", m_settings->alarmVolume()},
        {"notificationVolume", m_settings->notificationVolume()},
        {"systemVolume", m_settings->systemVolume()},
        {"dndEnabled", m_settings->dndEnabled()},
        {"vibrationEnabled", m_settings->vibrationEnabled()},
        {"audioProfile", m_settings->audioProfile()},
        {"screenTimeout", m_settings->screenTimeout()},
        {"autoBrightness", m_settings->autoBrightness()},
        {"statusBarClockPosition", m_settings->statusBarClockPosition()},
        {"showNotificationsOnLockScreen", m_settings->showNotificationsOnLockScreen()},
        {"filterMobileFriendlyApps", m_settings->filterMobileFriendlyApps()},
        {"hiddenApps", m_settings->hiddenApps()},
        {"appSortOrder", m_settings->appSortOrder()},
        {"appGridColumns", m_settings->appGridColumns()},
        {"searchNativeApps", m_settings->searchNativeApps()},
        {"showNotificationBadges", m_settings->showNotificationBadges()},
        {"showFrequentApps", m_settings->showFrequentApps()},
        {"defaultApps", m_settings->defaultApps()},
        {"firstRunComplete", m_settings->firstRunComplete()},
        {"enabledQuickSettingsTiles", m_settings->enabledQuickSettingsTiles()},
        {"quickSettingsTileOrder", m_settings->quickSettingsTileOrder()},
        {"keyboardAutoCorrection", m_settings->keyboardAutoCorrection()},
        {"keyboardPredictiveText", m_settings->keyboardPredictiveText()},
        {"keyboardWordFling", m_settings->keyboardWordFling()},
        {"keyboardPredictiveSpacing", m_settings->keyboardPredictiveSpacing()},
        {"keyboardHapticStrength", m_settings->keyboardHapticStrength()},
    };
}

void SettingsObject::SetProperty(const QString &name, const QDBusVariant &value) {
    if (!requireSystem())
        return;

    const QVariant v = value.variant();
    // Map property name to typed setters (so signals + in-memory state stay consistent).
    if (name == "userScaleFactor")
        m_settings->setUserScaleFactor(v.toReal());
    else if (name == "wallpaperPath")
        m_settings->setWallpaperPath(v.toString());
    else if (name == "deviceName")
        m_settings->setDeviceName(v.toString());
    else if (name == "autoLock")
        m_settings->setAutoLock(v.toBool());
    else if (name == "autoLockTimeout")
        m_settings->setAutoLockTimeout(v.toInt());
    else if (name == "showNotificationPreviews")
        m_settings->setShowNotificationPreviews(v.toBool());
    else if (name == "timeFormat")
        m_settings->setTimeFormat(v.toString());
    else if (name == "dateFormat")
        m_settings->setDateFormat(v.toString());
    else if (name == "ringtone")
        m_settings->setRingtone(v.toString());
    else if (name == "notificationSound")
        m_settings->setNotificationSound(v.toString());
    else if (name == "alarmSound")
        m_settings->setAlarmSound(v.toString());
    else if (name == "mediaVolume")
        m_settings->setMediaVolume(v.toReal());
    else if (name == "ringtoneVolume")
        m_settings->setRingtoneVolume(v.toReal());
    else if (name == "alarmVolume")
        m_settings->setAlarmVolume(v.toReal());
    else if (name == "notificationVolume")
        m_settings->setNotificationVolume(v.toReal());
    else if (name == "systemVolume")
        m_settings->setSystemVolume(v.toReal());
    else if (name == "dndEnabled")
        m_settings->setDndEnabled(v.toBool());
    else if (name == "vibrationEnabled")
        m_settings->setVibrationEnabled(v.toBool());
    else if (name == "audioProfile")
        m_settings->setAudioProfile(v.toString());
    else if (name == "screenTimeout")
        m_settings->setScreenTimeout(v.toInt());
    else if (name == "autoBrightness")
        m_settings->setAutoBrightness(v.toBool());
    else if (name == "statusBarClockPosition")
        m_settings->setStatusBarClockPosition(v.toString());
    else if (name == "showNotificationsOnLockScreen")
        m_settings->setShowNotificationsOnLockScreen(v.toBool());
    else if (name == "filterMobileFriendlyApps")
        m_settings->setFilterMobileFriendlyApps(v.toBool());
    else if (name == "hiddenApps")
        m_settings->setHiddenApps(v.toStringList());
    else if (name == "appSortOrder")
        m_settings->setAppSortOrder(v.toString());
    else if (name == "appGridColumns")
        m_settings->setAppGridColumns(v.toInt());
    else if (name == "searchNativeApps")
        m_settings->setSearchNativeApps(v.toBool());
    else if (name == "showNotificationBadges")
        m_settings->setShowNotificationBadges(v.toBool());
    else if (name == "showFrequentApps")
        m_settings->setShowFrequentApps(v.toBool());
    else if (name == "defaultApps")
        m_settings->setDefaultApps(v.toMap());
    else if (name == "firstRunComplete")
        m_settings->setFirstRunComplete(v.toBool());
    else if (name == "enabledQuickSettingsTiles")
        m_settings->setEnabledQuickSettingsTiles(v.toStringList());
    else if (name == "quickSettingsTileOrder")
        m_settings->setQuickSettingsTileOrder(v.toStringList());
    else if (name == "keyboardAutoCorrection")
        m_settings->setKeyboardAutoCorrection(v.toBool());
    else if (name == "keyboardPredictiveText")
        m_settings->setKeyboardPredictiveText(v.toBool());
    else if (name == "keyboardWordFling")
        m_settings->setKeyboardWordFling(v.toBool());
    else if (name == "keyboardPredictiveSpacing")
        m_settings->setKeyboardPredictiveSpacing(v.toBool());
    else if (name == "keyboardHapticStrength")
        m_settings->setKeyboardHapticStrength(v.toString());
    else
        sendErrorReply(QDBusError::InvalidArgs, "Unknown settings property: " + name);
}

QStringList SettingsObject::AvailableRingtones() {
    if (!requireSystem())
        return {};
    return m_settings->availableRingtones();
}

QStringList SettingsObject::AvailableNotificationSounds() {
    if (!requireSystem())
        return {};
    return m_settings->availableNotificationSounds();
}

QStringList SettingsObject::AvailableAlarmSounds() {
    if (!requireSystem())
        return {};
    return m_settings->availableAlarmSounds();
}

QStringList SettingsObject::ScreenTimeoutOptions() {
    if (!requireSystem())
        return {};
    return m_settings->screenTimeoutOptions();
}

int SettingsObject::ScreenTimeoutValue(const QString &option) {
    if (!requireSystem())
        return 0;
    return m_settings->screenTimeoutValue(option);
}

QString SettingsObject::FormatSoundName(const QString &path) {
    if (!requireSystem())
        return {};
    return m_settings->formatSoundName(path);
}

QString SettingsObject::AssetUrl(const QString &relativePath) {
    if (!requireSystem())
        return {};
    return m_settings->assetUrl(relativePath);
}

QDBusVariant SettingsObject::Get(const QString &key, const QDBusVariant &defaultValue) {
    // App-scoped keys (e.g. "clock/...") are allowed with storage permission and are isolated
    // by enforcing the "appId/" prefix.
    if (isAppScopedKey(key)) {
        if (!requireStorage())
            return QDBusVariant();
        return QDBusVariant(m_settings->get(key, defaultValue.variant()));
    }

    if (!requireSystem())
        return QDBusVariant();
    return QDBusVariant(m_settings->get(key, defaultValue.variant()));
}

void SettingsObject::Set(const QString &key, const QDBusVariant &value) {
    if (isAppScopedKey(key)) {
        if (!requireStorage())
            return;
        m_settings->set(key, value.variant());
        return;
    }

    if (!requireSystem())
        return;
    m_settings->set(key, value.variant());
}

void SettingsObject::Sync() {
    // Sync can be used by apps persisting their app-scoped keys.
    // If the caller has either system or storage permission, allow it.
    if (!requireSystem()) {
        if (!requireStorage())
            return;
    }
    m_settings->sync();
}

// ---- BluetoothObject ----

BluetoothObject::BluetoothObject(BluetoothManager *bt, MarathonPermissionManager *permissions,
                                 AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_bt(bt)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_bt);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_bt, &BluetoothManager::enabledChanged, this, push);
    QObject::connect(m_bt, &BluetoothManager::scanningChanged, this, push);
    QObject::connect(m_bt, &BluetoothManager::devicesChanged, this, push);
    QObject::connect(m_bt, &BluetoothManager::pairedDevicesChanged, this, push);
    QObject::connect(m_bt, &BluetoothManager::availableChanged, this, push);
    QObject::connect(m_bt, &BluetoothManager::adapterNameChanged, this, push);

    QObject::connect(m_bt, &BluetoothManager::pairingFailed, this, &BluetoothObject::PairingFailed);
    QObject::connect(m_bt, &BluetoothManager::pairingSucceeded, this,
                     &BluetoothObject::PairingSucceeded);
    QObject::connect(m_bt, &BluetoothManager::pinRequested, this, &BluetoothObject::PinRequested);
    QObject::connect(m_bt, &BluetoothManager::passkeyRequested, this,
                     &BluetoothObject::PasskeyRequested);
    QObject::connect(m_bt, &BluetoothManager::passkeyConfirmation, this,
                     &BluetoothObject::PasskeyConfirmation);
}

QString BluetoothObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool BluetoothObject::requireSystem() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"system"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: system");
        return false;
    }
    return true;
}

QVariantList BluetoothObject::buildDevices(bool pairedOnly) const {
    QVariantList           out;
    const QList<QObject *> list = pairedOnly ? m_bt->pairedDevices() : m_bt->devices();
    for (QObject *d : list) {
        if (!d)
            continue;
        // IMPORTANT: wrap complex nested payloads in QDBusVariant for reliable QtDBus marshalling.
        // (List-of-map inside a{sv} can otherwise arrive empty on the client.)
        out.push_back(QVariant::fromValue(QDBusVariant(QVariantMap{
            {"address", d->property("address").toString()},
            {"name", d->property("name").toString()},
            {"alias", d->property("alias").toString()},
            {"paired", d->property("paired").toBool()},
            {"connected", d->property("connected").toBool()},
            {"trusted", d->property("trusted").toBool()},
            {"rssi", d->property("rssi").toInt()},
            {"icon", d->property("icon").toString()},
        })));
    }
    return out;
}

QVariantMap BluetoothObject::buildState() const {
    return {
        {"available", m_bt->available()},      {"enabled", m_bt->enabled()},
        {"scanning", m_bt->scanning()},        {"discoverable", m_bt->discoverable()},
        {"adapterName", m_bt->adapterName()},  {"devices", buildDevices(false)},
        {"pairedDevices", buildDevices(true)},
    };
}

QVariantMap BluetoothObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void BluetoothObject::SetEnabled(bool enabled) {
    if (!requireSystem())
        return;
    m_bt->setEnabled(enabled);
}

void BluetoothObject::StartScan() {
    if (!requireSystem())
        return;
    m_bt->startScan();
}

void BluetoothObject::StopScan() {
    if (!requireSystem())
        return;
    m_bt->stopScan();
}

void BluetoothObject::ConnectDevice(const QString &address) {
    if (!requireSystem())
        return;
    m_bt->connectDevice(address);
}

void BluetoothObject::DisconnectDevice(const QString &address) {
    if (!requireSystem())
        return;
    m_bt->disconnectDevice(address);
}

void BluetoothObject::PairDevice(const QString &address, const QString &pin) {
    if (!requireSystem())
        return;
    m_bt->pairDevice(address, pin);
}

void BluetoothObject::UnpairDevice(const QString &address) {
    if (!requireSystem())
        return;
    m_bt->unpairDevice(address);
}

void BluetoothObject::ConfirmPairing(const QString &address, bool confirmed) {
    if (!requireSystem())
        return;
    m_bt->confirmPairing(address, confirmed);
}

void BluetoothObject::CancelPairing(const QString &address) {
    if (!requireSystem())
        return;
    m_bt->cancelPairing(address);
}

// ---- DisplayObject ----

DisplayObject::DisplayObject(DisplayManagerCpp *display, MarathonPermissionManager *permissions,
                             AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_display(display)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_display);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_display, &DisplayManagerCpp::availableChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::autoBrightnessEnabledChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::rotationLockedChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::screenTimeoutChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::brightnessChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::nightLightEnabledChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::nightLightTemperatureChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::nightLightScheduleChanged, this, push);
    QObject::connect(m_display, &DisplayManagerCpp::screenStateChanged, this, push);
}

QString DisplayObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool DisplayObject::requireSystem() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"system"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: system");
        return false;
    }
    return true;
}

QVariantMap DisplayObject::buildState() const {
    return {
        {"available", m_display->available()},
        {"autoBrightnessEnabled", m_display->autoBrightnessEnabled()},
        {"rotationLocked", m_display->rotationLocked()},
        {"screenTimeout", m_display->screenTimeout()},
        {"screenTimeoutString", m_display->screenTimeoutString()},
        {"brightness", m_display->brightness()},
        {"nightLightEnabled", m_display->nightLightEnabled()},
        {"nightLightTemperature", m_display->nightLightTemperature()},
        {"nightLightSchedule", m_display->nightLightSchedule()},
    };
}

QVariantMap DisplayObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void DisplayObject::SetAutoBrightness(bool enabled) {
    if (!requireSystem())
        return;
    m_display->setAutoBrightness(enabled);
}

void DisplayObject::SetRotationLock(bool locked) {
    if (!requireSystem())
        return;
    m_display->setRotationLock(locked);
}

void DisplayObject::SetScreenTimeout(int seconds) {
    if (!requireSystem())
        return;
    m_display->setScreenTimeout(seconds);
}

void DisplayObject::SetBrightness(double brightness) {
    if (!requireSystem())
        return;
    m_display->setBrightness(brightness);
}

void DisplayObject::SetNightLightEnabled(bool enabled) {
    if (!requireSystem())
        return;
    m_display->setNightLightEnabled(enabled);
}

void DisplayObject::SetNightLightTemperature(int temperature) {
    if (!requireSystem())
        return;
    m_display->setNightLightTemperature(temperature);
}

void DisplayObject::SetNightLightSchedule(const QString &schedule) {
    if (!requireSystem())
        return;
    m_display->setNightLightSchedule(schedule);
}

void DisplayObject::SetScreenState(bool on) {
    if (!requireSystem())
        return;
    m_display->setScreenState(on);
}

// ---- PowerObject ----

PowerObject::PowerObject(PowerManagerCpp *power, MarathonPermissionManager *permissions,
                         AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_power(power)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_power);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_power, &PowerManagerCpp::batteryLevelChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::isChargingChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::isPluggedInChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::isPowerSaveModeChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::estimatedBatteryTimeChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::powerProfileChanged, this, push);
}

QString PowerObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool PowerObject::requireSystem() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"system"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: system");
        return false;
    }
    return true;
}

QVariantMap PowerObject::buildState() const {
    return {
        {"batteryLevel", m_power->batteryLevel()},
        {"isCharging", m_power->isCharging()},
        {"isPluggedIn", m_power->isPluggedIn()},
        {"isPowerSaveMode", m_power->isPowerSaveMode()},
        {"estimatedBatteryTime", m_power->estimatedBatteryTime()},
        {"powerProfile", m_power->powerProfile()},
        {"powerProfilesSupported", m_power->powerProfilesSupported()},
    };
}

QVariantMap PowerObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void PowerObject::SetPowerSaveMode(bool enabled) {
    if (!requireSystem())
        return;
    m_power->setPowerSaveMode(enabled);
}

void PowerObject::SetPowerProfile(const QString &profile) {
    if (!requireSystem())
        return;
    m_power->setPowerProfile(profile);
}

void PowerObject::Suspend() {
    if (!requireSystem())
        return;
    m_power->suspend();
}

void PowerObject::Restart() {
    if (!requireSystem())
        return;
    m_power->restart();
}

void PowerObject::Shutdown() {
    if (!requireSystem())
        return;
    m_power->shutdown();
}

// ---- AudioObject ----

static QVariantList audioStreamsToVariantList(AudioManagerCpp *audio) {
    QVariantList out;
    if (!audio || !audio->streams())
        return out;

    auto     *m    = audio->streams();
    const int rows = m->rowCount();
    out.reserve(rows);

    for (int row = 0; row < rows; ++row) {
        const QModelIndex idx = m->index(row, 0);
        QVariantMap       s;
        s.insert("streamId", m->data(idx, AudioStreamModel::IdRole));
        s.insert("name", m->data(idx, AudioStreamModel::NameRole));
        s.insert("appName", m->data(idx, AudioStreamModel::AppNameRole));
        s.insert("volume", m->data(idx, AudioStreamModel::VolumeRole));
        s.insert("muted", m->data(idx, AudioStreamModel::MutedRole));
        s.insert("mediaClass", m->data(idx, AudioStreamModel::MediaClassRole));
        out.push_back(s);
    }
    return out;
}

AudioObject::AudioObject(AudioManagerCpp *audio, AudioPolicyController *policy,
                         MarathonPermissionManager *permissions, AppLaunchService *launchService,
                         QObject *parent)
    : QObject(parent)
    , m_audio(audio)
    , m_policy(policy)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_audio);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_audio, &AudioManagerCpp::availableChanged, this, push);
    QObject::connect(m_audio, &AudioManagerCpp::volumeChanged, this, push);
    QObject::connect(m_audio, &AudioManagerCpp::mutedChanged, this, push);
    QObject::connect(m_audio, &AudioManagerCpp::streamsChanged, this, push);
}

QString AudioObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool AudioObject::requireSystem() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"system"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: system");
        return false;
    }
    return true;
}

QVariantMap AudioObject::buildState() const {
    return {
        {"available", m_audio->available()},
        {"volume", m_audio->volume()},
        {"muted", m_audio->muted()},
        {"perAppVolumeSupported", m_audio->perAppVolumeSupported()},
        {"streams", audioStreamsToVariantList(m_audio)},
    };
}

QVariantMap AudioObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void AudioObject::SetVolume(double volume) {
    if (!requireSystem())
        return;
    // Use policy controller if present to keep SettingsManager.systemVolume in sync.
    if (m_policy) {
        m_policy->setMasterVolume(volume);
    } else {
        m_audio->setVolume(volume);
    }
}

void AudioObject::SetMuted(bool muted) {
    if (!requireSystem())
        return;
    if (m_policy) {
        m_policy->setMuted(muted);
    } else {
        m_audio->setMuted(muted);
    }
}

void AudioObject::SetStreamVolume(int streamId, double volume) {
    if (!requireSystem())
        return;
    m_audio->setStreamVolume(streamId, volume);
}

void AudioObject::SetStreamMuted(int streamId, bool muted) {
    if (!requireSystem())
        return;
    m_audio->setStreamMuted(streamId, muted);
}

void AudioObject::RefreshStreams() {
    if (!requireSystem())
        return;
    m_audio->refreshStreams();
}

void AudioObject::SetDoNotDisturb(bool enabled) {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->setDoNotDisturb(enabled);
}

void AudioObject::SetAudioProfile(const QString &profile) {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->setAudioProfile(profile);
}

void AudioObject::PlayRingtone() {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->playRingtone();
}

void AudioObject::StopRingtone() {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->stopRingtone();
}

void AudioObject::PlayNotificationSound() {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->playNotificationSound();
}

void AudioObject::PlayAlarmSound() {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->playAlarmSound();
}

void AudioObject::StopAlarmSound() {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->stopAlarmSound();
}

void AudioObject::PreviewSound(const QString &soundPath) {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->previewSound(soundPath);
}

void AudioObject::VibratePattern(const QVariantList &pattern) {
    if (!requireSystem())
        return;
    if (m_policy)
        m_policy->vibratePattern(pattern);
}

// ---- NetworkObject ----

NetworkObject::NetworkObject(NetworkManagerCpp *network, MarathonPermissionManager *permissions,
                             AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_network(network)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_network);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_network, &NetworkManagerCpp::wifiEnabledChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::wifiConnectedChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::wifiSsidChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::wifiSignalStrengthChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::ethernetConnectedChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::ethernetConnectionNameChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::wifiAvailableChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::bluetoothAvailableChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::hotspotSupportedChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::bluetoothEnabledChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::airplaneModeEnabledChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::availableNetworksChanged, this, push);

    QObject::connect(m_network, &NetworkManagerCpp::networkError, this,
                     &NetworkObject::NetworkError);
    QObject::connect(m_network, &NetworkManagerCpp::connectionSuccess, this,
                     &NetworkObject::ConnectionSuccess);
    QObject::connect(m_network, &NetworkManagerCpp::connectionFailed, this,
                     &NetworkObject::ConnectionFailed);
}

QString NetworkObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool NetworkObject::requireNetwork() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"network", "system"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: network");
        return false;
    }
    return true;
}

QVariantMap NetworkObject::buildState() const {
    // IMPORTANT: wrap complex nested payloads in QDBusVariant for reliable QtDBus marshalling.
    QVariantList       wrappedNetworks;
    const QVariantList nets = m_network->availableNetworks();
    wrappedNetworks.reserve(nets.size());
    for (const QVariant &v : nets) {
        wrappedNetworks.push_back(QVariant::fromValue(QDBusVariant(v)));
    }
    return {
        {"wifiEnabled", m_network->wifiEnabled()},
        {"wifiConnected", m_network->wifiConnected()},
        {"wifiSsid", m_network->wifiSsid()},
        {"wifiSignalStrength", m_network->wifiSignalStrength()},
        {"ethernetConnected", m_network->ethernetConnected()},
        {"ethernetConnectionName", m_network->ethernetConnectionName()},
        {"wifiAvailable", m_network->wifiAvailable()},
        {"bluetoothAvailable", m_network->bluetoothAvailable()},
        {"hotspotSupported", m_network->hotspotSupported()},
        {"bluetoothEnabled", m_network->bluetoothEnabled()},
        {"airplaneModeEnabled", m_network->airplaneModeEnabled()},
        {"availableNetworks", wrappedNetworks},
        {"hotspotActive", m_network->isHotspotActive()},
    };
}

QVariantMap NetworkObject::GetState() {
    if (!requireNetwork())
        return {};
    return buildState();
}

void NetworkObject::EnableWifi() {
    if (!requireNetwork())
        return;
    m_network->enableWifi();
}

void NetworkObject::DisableWifi() {
    if (!requireNetwork())
        return;
    m_network->disableWifi();
}

void NetworkObject::ToggleWifi() {
    if (!requireNetwork())
        return;
    m_network->toggleWifi();
}

void NetworkObject::ScanWifi() {
    if (!requireNetwork())
        return;
    m_network->scanWifi();
}

void NetworkObject::ConnectToNetwork(const QString &ssid, const QString &password) {
    if (!requireNetwork())
        return;
    m_network->connectToNetwork(ssid, password);
}

void NetworkObject::DisconnectWifi() {
    if (!requireNetwork())
        return;
    m_network->disconnectWifi();
}

void NetworkObject::SetAirplaneMode(bool enabled) {
    if (!requireNetwork())
        return;
    m_network->setAirplaneMode(enabled);
}

void NetworkObject::CreateHotspot(const QString &ssid, const QString &password) {
    if (!requireNetwork())
        return;
    m_network->createHotspot(ssid, password);
}

void NetworkObject::StopHotspot() {
    if (!requireNetwork())
        return;
    m_network->stopHotspot();
}

bool NetworkObject::IsHotspotActive() const {
    // Pure read: still enforce auth to avoid leaking state.
    if (!const_cast<NetworkObject *>(this)->requireNetwork())
        return false;
    return m_network->isHotspotActive();
}

// ---- MediaLibraryObject ----

MediaLibraryObject::MediaLibraryObject(MediaLibraryManager       *media,
                                       MarathonPermissionManager *permissions,
                                       AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_media(media)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_media);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    QObject::connect(m_media, &MediaLibraryManager::albumsChanged, this,
                     &MediaLibraryObject::AlbumsChanged);
    QObject::connect(m_media, &MediaLibraryManager::scanningChanged, this,
                     &MediaLibraryObject::ScanningChanged);
    QObject::connect(m_media, &MediaLibraryManager::scanComplete, this,
                     &MediaLibraryObject::ScanComplete);
    QObject::connect(m_media, &MediaLibraryManager::newMediaAdded, this,
                     &MediaLibraryObject::NewMediaAdded);
    QObject::connect(m_media, &MediaLibraryManager::libraryChanged, this,
                     &MediaLibraryObject::LibraryChanged);
    QObject::connect(m_media, &MediaLibraryManager::scanProgressChanged, this,
                     &MediaLibraryObject::ScanProgressChanged);
}

QString MediaLibraryObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool MediaLibraryObject::requireStorage() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"storage"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: storage");
        return false;
    }
    return true;
}

QVariantList MediaLibraryObject::Albums() {
    if (!requireStorage())
        return {};
    const QVariantList raw = m_media->albums();
    QVariantList       out;
    out.reserve(raw.size());
    for (const QVariant &v : raw) {
        out.push_back(QVariant::fromValue(QDBusVariant(v)));
    }
    return out;
}

bool MediaLibraryObject::IsScanning() const {
    // Strict for now: require permission even for read.
    if (!const_cast<MediaLibraryObject *>(this)->requireStorage())
        return false;
    return m_media->isScanning();
}

int MediaLibraryObject::PhotoCount() const {
    if (!const_cast<MediaLibraryObject *>(this)->requireStorage())
        return 0;
    return m_media->photoCount();
}

int MediaLibraryObject::VideoCount() const {
    if (!const_cast<MediaLibraryObject *>(this)->requireStorage())
        return 0;
    return m_media->videoCount();
}

int MediaLibraryObject::ScanProgress() const {
    if (!const_cast<MediaLibraryObject *>(this)->requireStorage())
        return 0;
    return m_media->scanProgress();
}

void MediaLibraryObject::ScanLibrary() {
    if (!requireStorage())
        return;
    m_media->scanLibrary();
}

void MediaLibraryObject::ScanLibraryAsync() {
    if (!requireStorage())
        return;
    m_media->scanLibraryAsync();
}

QVariantList MediaLibraryObject::GetPhotos(const QString &albumId) {
    if (!requireStorage())
        return {};
    const QVariantList raw = m_media->getPhotos(albumId);
    QVariantList       out;
    out.reserve(raw.size());
    for (const QVariant &v : raw) {
        out.push_back(QVariant::fromValue(QDBusVariant(v)));
    }
    return out;
}

QVariantList MediaLibraryObject::GetAllPhotos() {
    if (!requireStorage())
        return {};
    const QVariantList raw = m_media->getAllPhotos();
    QVariantList       out;
    out.reserve(raw.size());
    for (const QVariant &v : raw) {
        out.push_back(QVariant::fromValue(QDBusVariant(v)));
    }
    return out;
}

QVariantList MediaLibraryObject::GetVideos() {
    if (!requireStorage())
        return {};
    const QVariantList raw = m_media->getVideos();
    QVariantList       out;
    out.reserve(raw.size());
    for (const QVariant &v : raw) {
        out.push_back(QVariant::fromValue(QDBusVariant(v)));
    }
    return out;
}

QString MediaLibraryObject::GenerateThumbnail(const QString &filePath) {
    if (!requireStorage())
        return {};
    return m_media->generateThumbnail(filePath);
}

void MediaLibraryObject::DeleteMedia(int mediaId) {
    if (!requireStorage())
        return;
    m_media->deleteMedia(mediaId);
}

// ---- PermissionsObject ----

PermissionsObject::PermissionsObject(MarathonPermissionManager *permissions,
                                     AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_permissions, &MarathonPermissionManager::permissionGranted, this,
                     &PermissionsObject::PermissionGranted);
    QObject::connect(m_permissions, &MarathonPermissionManager::permissionDenied, this,
                     &PermissionsObject::PermissionDenied);
    QObject::connect(m_permissions, &MarathonPermissionManager::permissionRequested, this,
                     &PermissionsObject::PermissionRequested);
}

QString PermissionsObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool PermissionsObject::HasPermission(const QString &appId, const QString &permission) {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty() || caller != appId) {
        sendErrorReply(QDBusError::AccessDenied, "AppId spoofing or unknown caller");
        return false;
    }
    return m_permissions->hasPermission(caller, permission);
}

void PermissionsObject::RequestPermission(const QString &appId, const QString &permission) {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty() || caller != appId) {
        sendErrorReply(QDBusError::AccessDenied, "AppId spoofing or unknown caller");
        return;
    }
    m_permissions->requestPermission(caller, permission);
}

void PermissionsObject::SetPermission(const QString &appId, const QString &permission, bool granted,
                                      bool remember) {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty() || caller != appId) {
        sendErrorReply(QDBusError::AccessDenied, "AppId spoofing or unknown caller");
        return;
    }
    m_permissions->setPermission(caller, permission, granted, remember);
}

// ---- ContactsObject ----

ContactsObject::ContactsObject(ContactsManager *contacts, MarathonPermissionManager *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_contacts(contacts)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_contacts);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_contacts, &ContactsManager::contactsChanged, this,
                     &ContactsObject::ContactsChanged);
    QObject::connect(m_contacts, &ContactsManager::contactAdded, this,
                     &ContactsObject::ContactAdded);
    QObject::connect(m_contacts, &ContactsManager::contactUpdated, this,
                     &ContactsObject::ContactUpdated);
    QObject::connect(m_contacts, &ContactsManager::contactDeleted, this,
                     &ContactsObject::ContactDeleted);
}

QString ContactsObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool ContactsObject::requireContacts() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"contacts"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: contacts");
        return false;
    }
    return true;
}

QVariantList ContactsObject::GetContacts() {
    if (!requireContacts())
        return {};
    return m_contacts->contacts();
}

QVariantMap ContactsObject::GetContact(int id) {
    if (!requireContacts())
        return {};
    return m_contacts->getContact(id);
}

QVariantMap ContactsObject::GetContactByNumber(const QString &phoneNumber) {
    if (!requireContacts())
        return {};
    return m_contacts->getContactByNumber(phoneNumber);
}

QVariantList ContactsObject::SearchContacts(const QString &query) {
    if (!requireContacts())
        return {};
    return m_contacts->searchContacts(query);
}

void ContactsObject::AddContact(const QString &name, const QString &phone, const QString &email) {
    if (!requireContacts())
        return;
    m_contacts->addContact(name, phone, email);
}

void ContactsObject::UpdateContact(int id, const QVariantMap &data) {
    if (!requireContacts())
        return;
    m_contacts->updateContact(id, data);
}

void ContactsObject::DeleteContact(int id) {
    if (!requireContacts())
        return;
    m_contacts->deleteContact(id);
}

// ---- CallHistoryObject ----

CallHistoryObject::CallHistoryObject(CallHistoryManager        *callHistory,
                                     MarathonPermissionManager *permissions,
                                     AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_callHistory(callHistory)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_callHistory);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_callHistory, &CallHistoryManager::historyChanged, this,
                     &CallHistoryObject::HistoryChanged);
    QObject::connect(m_callHistory, &CallHistoryManager::callAdded, this,
                     &CallHistoryObject::CallAdded);
}

QString CallHistoryObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool CallHistoryObject::requirePhone() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    // Compatibility: phone apps may request "phone" (legacy) instead of "telephony".
    if (!hasAnyPermission(m_permissions, caller, {"telephony", "phone"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: telephony/phone");
        return false;
    }
    return true;
}

QVariantList CallHistoryObject::GetHistory() {
    if (!requirePhone())
        return {};
    return m_callHistory->history();
}

QVariantMap CallHistoryObject::GetCallById(int id) {
    if (!requirePhone())
        return {};
    return m_callHistory->getCallById(id);
}

QVariantList CallHistoryObject::GetCallsByNumber(const QString &number) {
    if (!requirePhone())
        return {};
    return m_callHistory->getCallsByNumber(number);
}

void CallHistoryObject::AddCall(const QString &number, const QString &type, qint64 timestamp,
                                int duration) {
    if (!requirePhone())
        return;
    m_callHistory->addCall(number, type, timestamp, duration);
}

void CallHistoryObject::DeleteCall(int id) {
    if (!requirePhone())
        return;
    m_callHistory->deleteCall(id);
}

void CallHistoryObject::ClearHistory() {
    if (!requirePhone())
        return;
    m_callHistory->clearHistory();
}

// ---- TelephonyObject ----

TelephonyObject::TelephonyObject(TelephonyService          *telephony,
                                 MarathonPermissionManager *permissions,
                                 AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_telephony(telephony)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_telephony);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    QObject::connect(m_telephony, &TelephonyService::callStateChanged, this,
                     &TelephonyObject::CallStateChanged);
    QObject::connect(m_telephony, &TelephonyService::incomingCall, this,
                     &TelephonyObject::IncomingCall);
    QObject::connect(m_telephony, &TelephonyService::callFailed, this,
                     &TelephonyObject::CallFailed);
    QObject::connect(m_telephony, &TelephonyService::modemChanged, this,
                     &TelephonyObject::ModemChanged);
    QObject::connect(m_telephony, &TelephonyService::activeNumberChanged, this,
                     &TelephonyObject::ActiveNumberChanged);
}

QString TelephonyObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool TelephonyObject::requirePhone() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"telephony", "phone"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: telephony/phone");
        return false;
    }
    return true;
}

QString TelephonyObject::CallState() const {
    // Allow read without permission? keep strict for now.
    if (!const_cast<TelephonyObject *>(this)->requirePhone())
        return {};
    return m_telephony->callState();
}

bool TelephonyObject::HasModem() const {
    if (!const_cast<TelephonyObject *>(this)->requirePhone())
        return false;
    return m_telephony->hasModem();
}

QString TelephonyObject::ActiveNumber() const {
    if (!const_cast<TelephonyObject *>(this)->requirePhone())
        return {};
    return m_telephony->activeNumber();
}

void TelephonyObject::Dial(const QString &number) {
    if (!requirePhone())
        return;
    m_telephony->dial(number);
}

void TelephonyObject::Answer() {
    if (!requirePhone())
        return;
    m_telephony->answer();
}

void TelephonyObject::Hangup() {
    if (!requirePhone())
        return;
    m_telephony->hangup();
}

void TelephonyObject::SendDTMF(const QString &digit) {
    if (!requirePhone())
        return;
    m_telephony->sendDTMF(digit);
}

// ---- SmsObject ----

SmsObject::SmsObject(SMSService *sms, MarathonPermissionManager *permissions,
                     AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_sms(sms)
    , m_permissions(permissions)
    , m_launchService(launchService) {
    Q_ASSERT(m_sms);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_sms, &SMSService::messageReceived, this, &SmsObject::MessageReceived);
    QObject::connect(m_sms, &SMSService::messageSent, this, &SmsObject::MessageSent);
    QObject::connect(m_sms, &SMSService::sendFailed, this, &SmsObject::SendFailed);
    QObject::connect(m_sms, &SMSService::conversationsChanged, this,
                     &SmsObject::ConversationsChanged);
}

QString SmsObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool SmsObject::requireSms() {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, {"sms", "phone"})) {
        sendErrorReply(QDBusError::AccessDenied, "Missing permission: sms/phone");
        return false;
    }
    return true;
}

QVariantList SmsObject::GetConversations() {
    if (!requireSms())
        return {};
    return m_sms->conversations();
}

QVariantList SmsObject::GetMessages(const QString &conversationId) {
    if (!requireSms())
        return {};
    return m_sms->getMessages(conversationId);
}

void SmsObject::SendMessage(const QString &recipient, const QString &text) {
    if (!requireSms())
        return;
    m_sms->sendMessage(recipient, text);
}

void SmsObject::DeleteConversation(const QString &conversationId) {
    if (!requireSms())
        return;
    m_sms->deleteConversation(conversationId);
}

void SmsObject::MarkAsRead(const QString &conversationId) {
    if (!requireSms())
        return;
    m_sms->markAsRead(conversationId);
}

QString SmsObject::GenerateConversationId(const QString &number) {
    if (!requireSms())
        return {};
    return m_sms->generateConversationId(number);
}
