#include "shellservices.h"
#include "callerpid.h"
#include "marathon-shell-native/src/gate.cxxqt.h"
#include <algorithm>

#include "applaunchservice.h"
#include "foregroundapp.h"
#include "sessionstore.h"
#include "marathon-shell-native/src/permissions.cxxqt.h"
#include "settingsmanager.h"
#include "marathon-shell-native/src/audio.cxxqt.h"
#include "audiopolicycontroller.h"

#include "marathonappinstaller.h"
#include "../services/applifecyclemanager.h"
#include "marathonappregistry.h"
#include "marathonmanifest.h"
#include "dbusnormalize.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QProcess>
#include <QDBusError>
#include <QDBusMessage>
#include <QCoreApplication>

// cxx-qt makes a Rust i64 a QVariant of C long, which QtDBus cannot send:
// libdbus aborts on the half-written entry. Rust values pass through this.
static QVariant sendable(const QVariant &value) {
    switch (value.typeId()) {
        case QMetaType::Long: return QVariant::fromValue(qlonglong(value.value<long>()));
        case QMetaType::QVariantList: {
            QVariantList list = value.toList();
            for (QVariant &v : list)
                v = sendable(v);
            return list;
        }
        case QMetaType::QVariantMap: {
            QVariantMap map = value.toMap();
            for (QVariant &v : map)
                v = sendable(v);
            return map;
        }
        default: return value;
    }
}

// MARATHON_TEST_TRUSTED's synthetic caller (marathon::gate).
static const char *const MARATHON_TEST_CALLER_ID = "_marathon_test_caller";
static bool g_testBypassEnabled = qEnvironmentVariableIntValue("MARATHON_TEST_TRUSTED") != 0;

static bool hasAnyPermission(marathon::Permissions *pm, const QString &appId,
                             const QStringList &perms) {
    if (g_testBypassEnabled && appId == QLatin1String(MARATHON_TEST_CALLER_ID))
        return true;
    if (marathon::gate::service_allows(appId, perms))
        return true;
    return std::any_of(perms.cbegin(), perms.cend(),
                       [&](const QString &p) { return pm && pm->hasPermission(appId, p); });
}

static bool checkRateLimit(const QDBusContext &ctx, const QString &method) {
    return !ctx.calledFromDBus() || marathon::gate::within_rate(ctx.message().service(), method);
}

static QString callerOf(const QDBusContext &ctx) {
    return ctx.calledFromDBus() ?
        marathon::gate::caller_of_pid(callerPid(ctx.connection(), ctx.message().service())) :
        QString();
}

IpcPermissionedService::IpcPermissionedService(marathon::Permissions *permissions,
                                               AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_permissions(permissions)
    , m_launchService(launchService) {}

QString IpcPermissionedService::callerAppIdOrEmpty() const {
    return callerOf(*this);
}

bool IpcPermissionedService::requirePermission(const QString     &rateLimitKey,
                                               const QStringList &permissions) {
    return admit({}, rateLimitKey, permissions);
}

bool IpcPermissionedService::admit(const QString &sender, const QString &rateLimitKey,
                                   const QStringList &permissions) {
    if (!calledFromDBus()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    const QString who     = sender.isEmpty() ? message().service() : sender;
    const QString refusal = marathon::gate::refusal(callerPid(connection(), who), who, rateLimitKey,
                                                    permissions);
    if (refusal.isEmpty())
        return true;
    sendErrorReply(refusal.section(QLatin1Char('\n'), 0, 0), refusal.section(QLatin1Char('\n'), 1));
    return false;
}

SettingsObject::SettingsObject(SettingsManager *settings, marathon::Permissions *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_settings(settings) {
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
    QObject::connect(m_settings, &SettingsManager::reduceMotionChanged, this,
                     [this, emitProp]() { emitProp("reduceMotion", m_settings->reduceMotion()); });
    QObject::connect(m_settings, &SettingsManager::timeZoneChanged, this,
                     [this, emitProp]() { emitProp("timeZone", m_settings->timeZone()); });
    QObject::connect(m_settings, &SettingsManager::timeFormatChanged, this,
                     [this, emitProp]() { emitProp("timeFormat", m_settings->timeFormat()); });
    QObject::connect(
        m_settings, &SettingsManager::automaticTimeChanged, this,
        [this, emitProp]() { emitProp("automaticTime", m_settings->automaticTime()); });
    QObject::connect(m_settings, &SettingsManager::automaticTimeZoneChanged, this,
                     [this, emitProp]() {
                         emitProp("automaticTimeZone", m_settings->automaticTimeZone());
                     });
    QObject::connect(m_settings, &SettingsManager::dateTimeChangeFailed, this,
                     &SettingsObject::DateTimeChangeFailed);
    // What a sound source (Deckard's Android) follows to stay quiet.
    QObject::connect(m_settings, &SettingsManager::dndEnabledChanged, this,
                     [this, emitProp]() { emitProp("dndEnabled", m_settings->dndEnabled()); });
    QObject::connect(m_settings, &SettingsManager::audioProfileChanged, this,
                     [this, emitProp]() { emitProp("audioProfile", m_settings->audioProfile()); });
    QObject::connect(m_settings, &SettingsManager::vibrationEnabledChanged, this, [this, emitProp]() {
        emitProp("vibrationEnabled", m_settings->vibrationEnabled());
    });
    QObject::connect(m_settings, &SettingsManager::mediaVolumeChanged, this,
                     [this, emitProp]() { emitProp("mediaVolume", m_settings->mediaVolume()); });
    QObject::connect(m_settings, &SettingsManager::ringtoneVolumeChanged, this, [this, emitProp]() {
        emitProp("ringtoneVolume", m_settings->ringtoneVolume());
    });
    QObject::connect(m_settings, &SettingsManager::alarmVolumeChanged, this,
                     [this, emitProp]() { emitProp("alarmVolume", m_settings->alarmVolume()); });
    QObject::connect(m_settings, &SettingsManager::notificationVolumeChanged, this,
                     [this, emitProp]() {
                         emitProp("notificationVolume", m_settings->notificationVolume());
                     });
    QObject::connect(m_settings, &SettingsManager::systemVolumeChanged, this, [this, emitProp]() {
        emitProp("systemVolume", m_settings->systemVolume());
    });
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
    QObject::connect(m_settings, &SettingsManager::appNotificationSettingsChanged, this,
                     [this, emitProp]() {
                         emitProp("appNotificationSettings", m_settings->appNotificationSettings());
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
    QObject::connect(
        m_settings, &SettingsManager::keyboardLanguageChanged, this,
        [this, emitProp]() { emitProp("keyboardLanguage", m_settings->keyboardLanguage()); });
    QObject::connect(m_settings, &SettingsManager::keyboardAutoCapitalizeChanged, this,
                     [this, emitProp]() {
                         emitProp("keyboardAutoCapitalize", m_settings->keyboardAutoCapitalize());
                     });
}

bool SettingsObject::isAppScopedKey(const QString &key) const {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty())
        return false;
    return key.startsWith(caller + "/");
}

QVariantMap SettingsObject::GetState() {
    // GetState is a READ of the global settings snapshot — userScaleFactor,
    // wallpaperPath, timeFormat, theme tokens etc. Every app reads these to
    // size its UI correctly. Gating on "system" forced every app launch to
    // prompt the user for a permission whose dialog itself says it can't
    // be granted (it's "restricted to system apps"), which created a no-op
    // trap: Music, Gallery, Notes, Calendar, Clock all hit the dialog,
    // user denies / dismisses, app then renders at the wrong scale.
    // Writes (SetProperty / Set) keep the gate.
    if (!checkRateLimit(*this, "Settings.GetState")) {
        sendErrorReply(QDBusError::LimitsExceeded, "Rate limit exceeded");
        return {};
    }

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
        {"reduceMotion", m_settings->reduceMotion()},
        {"timeZone", m_settings->timeZone()},
        {"automaticTime", m_settings->automaticTime()},
        {"automaticTimeZone", m_settings->automaticTimeZone()},
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
        {"appNotificationSettings", m_settings->appNotificationSettings()},
        {"showFrequentApps", m_settings->showFrequentApps()},
        {"defaultApps", m_settings->defaultApps()},
        {"firstRunComplete", m_settings->firstRunComplete()},
        {"enabledQuickSettingsTiles", m_settings->enabledQuickSettingsTiles()},
        {"quickSettingsTileOrder", m_settings->quickSettingsTileOrder()},
        {"keyboardAutoCorrection", m_settings->keyboardAutoCorrection()},
        {"keyboardPredictiveText", m_settings->keyboardPredictiveText()},
        {"keyboardHapticStrength", m_settings->keyboardHapticStrength()},
        {"keyboardLanguage", m_settings->keyboardLanguage()},
        {"keyboardAutoCapitalize", m_settings->keyboardAutoCapitalize()},
    };
}

void SettingsObject::SetProperty(const QString &name, const QDBusVariant &value) {
    if (!requireSystem())
        return;

    // Maps and lists inside the variant arrive as QDBusArgument, which
    // toMap()/toStringList() turn into empty values: picking a default app
    // wiped every default.
    QVariant v = value.variant();
    if (v.userType() == qMetaTypeId<QDBusArgument>()) {
        const QDBusArgument arg = v.value<QDBusArgument>();
        v = arg.currentType() == QDBusArgument::MapType ? QVariant(qdbus_cast<QVariantMap>(arg)) :
                                                          QVariant(qdbus_cast<QVariantList>(arg));
    }
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
    else if (name == "reduceMotion")
        m_settings->setReduceMotion(v.toBool());
    else if (name == "timeZone")
        m_settings->setTimeZone(v.toString());
    else if (name == "automaticTime")
        m_settings->setAutomaticTime(v.toBool());
    else if (name == "automaticTimeZone")
        m_settings->setAutomaticTimeZone(v.toBool());
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
    else if (name == "appNotificationSettings")
        m_settings->setAppNotificationSettings(v.toMap());
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
    else if (name == "keyboardHapticStrength")
        m_settings->setKeyboardHapticStrength(v.toString());
    else if (name == "keyboardLanguage")
        m_settings->setKeyboardLanguage(v.toString());
    else if (name == "keyboardAutoCapitalize")
        m_settings->setKeyboardAutoCapitalize(v.toBool());
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
    if (isAppScopedKey(key)) {
        if (!requireStorage())
            return QDBusVariant();
        return QDBusVariant(m_settings->get(key, defaultValue.variant()));
    }
    // The Calendar app's events, read-only, for callers with "calendar".
    if (key.startsWith(QLatin1String("calendar/"))
        && hasAnyPermission(m_permissions, callerAppIdOrEmpty(), {QStringLiteral("calendar")})) {
        if (!checkRateLimit(*this, "Settings.Calendar")) {
            sendErrorReply(QDBusError::LimitsExceeded, "Rate limit exceeded");
            return QDBusVariant();
        }
        return QDBusVariant(m_settings->get(key, defaultValue.variant()));
    }

    if (!requireSystem())
        return QDBusVariant();
    return QDBusVariant(m_settings->get(key, defaultValue.variant()));
}

void SettingsObject::Set(const QString &key, const QDBusVariant &value) {
    const QVariant v = normalizeDbusVariantDeep(value.variant());
    if (isAppScopedKey(key)) {
        if (!requireStorage())
            return;
        m_settings->set(key, v);
        return;
    }

    if (!requireSystem())
        return;
    m_settings->set(key, v);
}

void SettingsObject::Sync() {
    if (!requireSystem()) {
        if (!requireStorage())
            return;
    }
    m_settings->sync();
}

void SettingsObject::SetSystemTime(qlonglong msecsSinceEpoch) {
    if (!requireSystem())
        return;
    m_settings->setSystemTime(msecsSinceEpoch);
}

AudioObject::AudioObject(marathon::Audio *audio, AudioPolicyController *policy,
                         marathon::Permissions *permissions, AppLaunchService *launchService,
                         QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_audio(audio)
    , m_policy(policy) {
    Q_ASSERT(m_audio);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_audio, &marathon::Audio::availableChanged, this, push);
    QObject::connect(m_audio, &marathon::Audio::volumeChanged, this, push);
    QObject::connect(m_audio, &marathon::Audio::mutedChanged, this, push);
    QObject::connect(m_audio, &marathon::Audio::streamsChanged, this, push);
    if (m_policy) {
        QObject::connect(m_policy, &AudioPolicyController::audioProfileChanged, this, push);
        QObject::connect(m_policy, &AudioPolicyController::doNotDisturbChanged, this, push);
    }
}

QVariantMap AudioObject::buildState() const {
    return {
        {"available", m_audio->getAvailable()},
        {"volume", m_audio->getVolume()},
        {"muted", m_audio->getMuted()},
        {"perAppVolumeSupported", m_audio->perAppVolumeSupported()},
        {"streams", sendable(m_audio->getStreams())},
        {"doNotDisturb", m_policy ? m_policy->isDoNotDisturb() : false},
        {"audioProfile", m_policy ? m_policy->audioProfile() : QString()},
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

NavigationObject::NavigationObject(AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_launchService(launchService) {
    Q_ASSERT(m_launchService);
    connect(m_launchService, &AppLaunchService::routeForRunningApp, this,
            &NavigationObject::DeepLinkRequested);
}

QString NavigationObject::callerAppIdOrEmpty() const {
    return callerOf(*this);
}

bool NavigationObject::LaunchApp(const QString &appId) {
    // No caller auth needed — launching an app already in the manifest
    // registry exposes nothing the home grid wouldn't expose to a tap.
    // Lets `marathon-dev launch <id>` over SSH drive UI audits without
    // synthesising touches, which is fragile (overshoots the home-swipe
    // window and leaves the previous app capturing subsequent input).
    const QString caller = callerAppIdOrEmpty();

    if (appId.isEmpty()) {
        sendErrorReply(QDBusError::InvalidArgs, "appId cannot be empty");
        return false;
    }

    qInfo() << "[NavigationObject] LaunchApp requested by"
            << (caller.isEmpty() ? QStringLiteral("<external>") : caller) << "for" << appId;

    const bool ok = m_launchService->launchApp(QVariant(appId), nullptr, nullptr);
    if (ok) {
        emit AppLaunched(appId);
    } else {
        emit NavigationFailed(appId, "Failed to launch app");
    }
    return ok;
}

// No caller auth, as LaunchApp.
bool NavigationObject::StartAppInBackground(const QString &appId) {
    const QString caller = callerAppIdOrEmpty();

    if (appId.isEmpty()) {
        sendErrorReply(QDBusError::InvalidArgs, "appId cannot be empty");
        return false;
    }

    qInfo() << "[NavigationObject] StartAppInBackground requested by"
            << (caller.isEmpty() ? QStringLiteral("<external>") : caller) << "for" << appId;

    const bool ok = m_launchService->startAppInBackground(QVariant(appId));
    if (ok) {
        emit AppLaunched(appId);
    } else {
        emit NavigationFailed(appId, "Failed to launch app");
    }
    return ok;
}

bool NavigationObject::Navigate(const QString &uri) {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }

    if (!uri.startsWith("marathon://")) {
        sendErrorReply(QDBusError::InvalidArgs, "URI must start with marathon://");
        return false;
    }

    qInfo() << "[NavigationObject] Navigate requested by" << caller << "to" << uri;

    QString     path  = uri.mid(QString("marathon://").length());
    QStringList parts = path.split('/');
    QString     appId = parts.isEmpty() ? QString() : parts.first();

    if (appId.isEmpty()) {
        sendErrorReply(QDBusError::InvalidArgs, "Could not parse appId from URI");
        return false;
    }

    const bool ok = m_launchService->launchApp(QVariant(appId), nullptr, nullptr);
    if (ok) {
        emit AppLaunched(appId);
    } else {
        emit NavigationFailed(uri, "Failed to launch app");
    }
    return ok;
}

bool NavigationObject::LaunchAppWithRoute(const QString &appId, const QString &route,
                                          const QString &paramsJson) {
    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }

    if (appId.isEmpty()) {
        sendErrorReply(QDBusError::InvalidArgs, "appId cannot be empty");
        return false;
    }

    qInfo() << "[NavigationObject] LaunchAppWithRoute requested by" << caller << "for" << appId
            << "route:" << route << "params:" << paramsJson;

    // Route + params are plumbed to the runner via launchAppWithRoute, which
    // appends --route and sets MARATHON_APP_ROUTE / MARATHON_APP_ROUTE_PARAMS
    // in the spawned process's environment. The runner exposes these to QML
    // as context properties -- used by the lock-screen Emergency affordance.
    const bool ok =
        m_launchService->launchAppWithRoute(QVariant(appId), route, paramsJson, nullptr, nullptr);
    if (ok) {
        emit AppLaunched(appId);
    } else {
        emit NavigationFailed(appId, "Failed to launch app");
    }
    return ok;
}

// Services only (pilotd): an app could otherwise list what else is running.
void NavigationObject::setForegroundApp(ForegroundApp *foreground) {
    m_foreground = foreground;
    connect(foreground, &ForegroundApp::changed, this, &NavigationObject::ForegroundAppChanged);
}

QString NavigationObject::GetForegroundApp() {
    return m_foreground ? m_foreground->appId() : QString();
}

bool NavigationObject::requireService() {
    if (callerAppIdOrEmpty().startsWith(QLatin1String("service:")))
        return true;
    sendErrorReply(QDBusError::AccessDenied, "Only a session service may ask");
    return false;
}

bool NavigationObject::ExpectAppWindow(const QString &appId) {
    if (!requireService())
        return false;
    if (appId.isEmpty() || (m_session && m_session->isLocked()))
        return false;
    m_launchService->expectWindow(appId);
    return true;
}

void NavigationObject::SetAppWindowSecure(const QString &appId, bool secure) {
    if (requireService() && !appId.isEmpty())
        m_launchService->setAppSecure(appId, secure);
}

QString NavigationObject::AppIdForPid(uint pid) {
    if (!callerAppIdOrEmpty().startsWith(QLatin1String("service:"))) {
        sendErrorReply(QDBusError::AccessDenied, "Only a session service may ask");
        return {};
    }
    return m_launchService->appIdForPid(pid);
}

// Quick Settings shade control. No caller auth (see slot declaration): the
// shade surfaces only system toggles the lock screen already gates, and
// MarathonShell.qml refuses to open it while locked. mode: 0 hide, 1 show,
// 2 toggle -- routed through AppLaunchService::quickSettingsRequested so the
// lock guard + UIStore call stay in one place, in QML.
bool NavigationObject::ShowQuickSettings() {
    qInfo() << "[NavigationObject] ShowQuickSettings requested by"
            << (callerAppIdOrEmpty().isEmpty() ? QStringLiteral("<external>") : callerAppIdOrEmpty());
    m_launchService->requestQuickSettings(1);
    return true;
}

bool NavigationObject::HideQuickSettings() {
    qInfo() << "[NavigationObject] HideQuickSettings requested";
    m_launchService->requestQuickSettings(0);
    return true;
}

bool NavigationObject::ToggleQuickSettings() {
    qInfo() << "[NavigationObject] ToggleQuickSettings requested";
    m_launchService->requestQuickSettings(2);
    return true;
}

// === AppStoreObject ========================================================
//
// apps.marathonos.org serves no catalogue: it stays empty, and nothing in it
// downloads.

AppStoreObject::AppStoreObject(MarathonAppInstaller *installer,
                               marathon::Permissions *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_installer(installer) {
    if (m_installer) {
        connect(m_installer, &MarathonAppInstaller::uninstallComplete, this,
                &AppStoreObject::UninstallComplete);
        connect(m_installer, &MarathonAppInstaller::uninstallFailed, this,
                &AppStoreObject::UninstallFailed);
    }
}

void AppStoreObject::RunStoreUrl(const QString &url) {
    if (!requireSystem())
        return;
    // The handler validates each verb and ref itself; only its scheme is
    // checked here.
    if (!url.startsWith(QLatin1String("marathon-store://"))) {
        sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Not a marathon-store:// URL"));
        return;
    }
    if (!QProcess::startDetached(QStringLiteral("/usr/bin/marathon-store-handler"), {url}))
        sendErrorReply(QDBusError::Failed,
                       QStringLiteral("Could not start marathon-store-handler"));
}

bool AppStoreObject::CanUninstall(const QString &appId) {
    if (!requireSystem())
        return false;
    return m_installer && m_installer->canUninstall(appId);
}

void AppStoreObject::Uninstall(const QString &appId) {
    if (!requireSystem())
        return;
    if (m_installer)
        m_installer->uninstallApp(appId);
}

AppLifecycleObject::AppLifecycleObject(AppLifecycleManager *lifecycle,
                                       MarathonAppRegistry *appRegistry,
                                       AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_lifecycle(lifecycle)
    , m_appRegistry(appRegistry)
    , m_launchService(launchService) {}

quint32 AppLifecycleObject::BeginBackgroundTask(const QString &category, const QString &reason) {
    Q_UNUSED(reason);
    if (!m_lifecycle || !m_appRegistry || !m_launchService) {
        sendErrorReply(QDBusError::Failed, "AppLifecycle backend not ready");
        return 0;
    }
    if (!checkRateLimit(*this, QStringLiteral("BeginBackgroundTask"))) {
        sendErrorReply(QDBusError::LimitsExceeded, "Rate limit exceeded");
        return 0;
    }
    const QString appId = callerOf(*this);
    if (appId.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return 0;
    }
    // Manifest gate: the app must have declared this category at install
    // time. Apps can't widen their privileges at runtime.
    const QStringList declared = m_appRegistry->getBackgroundCapabilities(appId);
    if (!declared.contains(category)) {
        marathon::gate::log_denied(appId, "background:" + category);
        sendErrorReply(QDBusError::AccessDenied,
                       QStringLiteral("Category '%1' not declared in manifest").arg(category));
        return 0;
    }
    const quint32 handle = m_nextHandle++;
    m_handles.insert(handle, ActiveTask{appId, category});
    m_lifecycle->addCapability(appId, category);
    return handle;
}

bool AppLifecycleObject::EndBackgroundTask(quint32 handle) {
    auto it = m_handles.find(handle);
    if (it == m_handles.end())
        return false;
    const ActiveTask &task = it.value();
    m_handles.erase(it);
    // Refcount semantics: only release the capability when this was the
    // last outstanding handle holding (appId, category).
    bool stillHeld = false;
    for (auto h = m_handles.cbegin(); h != m_handles.cend(); ++h) {
        if (h->appId == task.appId && h->category == task.category) {
            stillHeld = true;
            break;
        }
    }
    if (!stillHeld && m_lifecycle)
        m_lifecycle->removeCapability(task.appId, task.category);
    return true;
}

QStringList AppLifecycleObject::GetMyCapabilities() {
    if (!m_lifecycle || !m_launchService)
        return {};
    const QString appId = callerOf(*this);
    if (appId.isEmpty())
        return {};
    return m_lifecycle->activeCapabilities(appId);
}
