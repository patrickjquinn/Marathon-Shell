#include "shellservices.h"
#include <unistd.h>
#include <fcntl.h>
#include <QDBusMetaType>
#include "mmsmanager.h"
#include "permissionauth.h"
#include "servicecaller.h"

#include "applaunchservice.h"
#include "foregroundapp.h"
#include "sessionstore.h"
#include "marathonpermissionmanager.h"
#include "settingsmanager.h"
#include "ambienceservice.h"
#include "wallpaperstore.h"
#include "securitymanager.h"
#include "bluetoothmanager.h"
#include "displaymanagercpp.h"
#include "flashlightmanagercpp.h"
#include "networkmanagercpp.h"
#include "modemmanagercpp.h"
#include "powermanagercpp.h"
#include "powerpolicycontroller.h"
#include "waketimers.h"
#include "audiomanagercpp.h"
#include "audiopolicycontroller.h"
#include "hapticmanager.h"
#include "sensormanagercpp.h"
#include "locationmanager.h"
#include "alarmmanagercpp.h"
#include "ratelimiter.h"
#include "securitylogger.h"

#include "callhistorymanager.h"
#include "contactsmanager.h"
#include "smsservice.h"
#include "audioroutingmanager.h"
#include "telephonyservice.h"
#include "medialibrarymanager.h"
#include "../services/updateservice.h"
#include "../services/factoryreset.h"
#include "../services/marathonappstoreservice.h"
#include "marathonappinstaller.h"
#include "../services/applifecyclemanager.h"
#include "marathonappregistry.h"
#include "marathonmanifest.h"
#include "davsyncengine.h"
#include "dbusnormalize.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QProcess>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QCoreApplication>
#include <QFile>
#include <QPointer>

// Function-local rather than namespace-scope: constructed on first use
// (thread-safe since C++11) instead of running a throwing initialiser
// before main().
static RateLimiter &ipcRateLimiter() {
    static RateLimiter limiter;
    return limiter;
}
static constexpr int RATE_LIMIT_MAX_CALLS = 30;
static constexpr int RATE_LIMIT_WINDOW_MS = 1000;

// Test bypass: when MARATHON_TEST_TRUSTED=1 is set in the shell's environment,
// external D-Bus callers are admitted as a synthetic trusted caller. Intended for
// automation/smoke tests only; never set this in production.
static const char *const MARATHON_TEST_CALLER_ID = "_marathon_test_caller";
static bool g_testBypassEnabled = qEnvironmentVariableIntValue("MARATHON_TEST_TRUSTED") != 0;

static bool hasAnyPermission(MarathonPermissionManager *pm, const QString &appId,
                             const QStringList &perms) {
    if (g_testBypassEnabled && appId == QLatin1String(MARATHON_TEST_CALLER_ID))
        return true;
    if (appId.startsWith(ServiceCaller::kPrefix))
        return ServiceCaller::allowed(appId, perms);
    if (!pm)
        return false;
    for (const auto &p : perms) {
        if (pm->hasPermission(appId, p))
            return true;
    }
    return false;
}

static bool checkRateLimit(const QDBusContext &ctx, const QString &method) {
    if (!ctx.calledFromDBus())
        return true;

    const QString sender = ctx.message().service();
    if (!ipcRateLimiter().tryAcquire(sender, method, RATE_LIMIT_MAX_CALLS, RATE_LIMIT_WINDOW_MS)) {
        double rate = ipcRateLimiter().getRate(sender, method);
        SecurityLogger::logRateLimitExceeded(sender, method, static_cast<int>(rate));
        return false;
    }
    return true;
}

static QString dbusCallerAppIdOrEmpty(const QDBusContext &ctx, AppLaunchService *als) {
    // Resolve the caller to a Marathon app id; return empty (= deny) when we
    // can't. Under MARATHON_TEST_TRUSTED, every non-resolution returns the
    // synthetic test caller instead -- never overriding a real resolution.
    const auto unresolved = []() {
        return g_testBypassEnabled ? QString::fromLatin1(MARATHON_TEST_CALLER_ID) : QString();
    };

    if (!ctx.calledFromDBus() || !als)
        return {};

    const QString sender   = ctx.message().service();
    auto          pidReply = ctx.connection().interface()->servicePid(sender);
    if (!pidReply.isValid())
        return unresolved();
    return appIdForCallerPid(static_cast<qint64>(pidReply.value()), als);
}

QString appIdForCallerPid(qint64 pid, AppLaunchService *als) {
    const auto unresolved = []() {
        return g_testBypassEnabled ? QString::fromLatin1(MARATHON_TEST_CALLER_ID) : QString();
    };
    if (QString mapped = als->appIdForPid(pid); !mapped.isEmpty())
        return mapped;
    if (QString service = ServiceCaller::resolve(pid); !service.isEmpty())
        return service;

    const qint64 shellPid = static_cast<qint64>(QCoreApplication::applicationPid());
    if (shellPid <= 0 || pid <= 0)
        return unresolved();

    // Confirm the caller is a marathon-app-runner whose ANCESTOR is this
    // shell. The direct parent is almost never the shell — the launch
    // chain is shell → bwrap (outer) → bwrap (inner) → marathon-app-runner,
    // so the immediate PPID is a bwrap helper.
    // Walk up the /proc PPID chain looking for the shell's PID; cap at
    // 8 hops so we don't churn on a runaway ancestor list. Without this
    // every D-Bus call from a sandboxed app fails the requireSystem /
    // requirePermission gate because the appId resolution falls through
    // to "unknown caller" — most visible as Settings reading brightness
    // = 0 % even when sysfs reports 100 %, but it breaks every IPC
    // surface (battery readback, system store, lifecycle manager).
    auto ppidOf = [](qint64 p) -> qint64 {
        QFile statFile(QStringLiteral("/proc/%1/stat").arg(p));
        if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text))
            return -1;
        const QByteArray statLine = statFile.readAll();
        const qsizetype  closeIdx = statLine.lastIndexOf(')');
        const QByteArray afterCmd =
            closeIdx < 0 ? QByteArray() : statLine.mid(closeIdx + 1).trimmed();
        const QList<QByteArray> parts = afterCmd.split(' ');
        if (parts.size() < 2)
            return -1;
        return parts.at(1).toLongLong();
    };

    bool   ancestorIsShell = false;
    qint64 cursor          = ppidOf(pid);
    for (int hop = 0; hop < 8 && cursor > 1; ++hop) {
        // Pool-adopted runners carry no --app-id in argv; their bwrap
        // ancestor is registered at adopt time instead.
        if (QString mapped = als->appIdForPid(cursor); !mapped.isEmpty()) {
            als->registerPidForAppId(pid, mapped);
            return mapped;
        }
        if (cursor == shellPid) {
            ancestorIsShell = true;
            break;
        }
        cursor = ppidOf(cursor);
    }
    if (!ancestorIsShell)
        return unresolved();

    QFile cmdFile(QStringLiteral("/proc/%1/cmdline").arg(pid));
    if (!cmdFile.open(QIODevice::ReadOnly))
        return unresolved();
    const QList<QByteArray> argv = cmdFile.readAll().split('\0');
    if (argv.isEmpty() || !QString::fromLocal8Bit(argv.value(0)).contains("marathon-app-runner"))
        return unresolved();

    QString appId;
    for (int i = 0; i + 1 < argv.size(); ++i) {
        if (argv[i] == "--app-id") {
            appId = QString::fromLocal8Bit(argv[i + 1]);
            break;
        }
    }
    if (appId.isEmpty() || !als->isMarathonAppId(appId))
        return unresolved();

    als->registerPidForAppId(pid, appId);
    return appId;
}

IpcPermissionedService::IpcPermissionedService(MarathonPermissionManager *permissions,
                                               AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_permissions(permissions)
    , m_launchService(launchService) {}

QString IpcPermissionedService::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
}

bool IpcPermissionedService::requirePermission(const QString     &rateLimitKey,
                                               const QStringList &permissions) {
    if (!checkRateLimit(*this, rateLimitKey)) {
        sendErrorReply(QDBusError::LimitsExceeded, "Rate limit exceeded");
        return false;
    }

    const QString caller = callerAppIdOrEmpty();
    if (caller.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return false;
    }
    if (!hasAnyPermission(m_permissions, caller, permissions)) {
        // An app that declared the permission but was never asked is asked
        // now; this call still fails, and the app retries on PermissionGranted.
        if (const QString asked = m_permissions->askIfUndecided(caller, permissions);
            !asked.isEmpty()) {
            SecurityLogger::logPermissionRequested(caller, asked);
            sendErrorReply(QDBusError::AccessDenied,
                           QStringLiteral("Permission requested: %1").arg(asked));
            return false;
        }
        const QString primary = permissions.isEmpty() ? QString() : permissions.first();
        SecurityLogger::logPermissionDenied(caller, primary);
        sendErrorReply(QDBusError::AccessDenied,
                       QStringLiteral("Missing permission: %1").arg(primary));
        return false;
    }
    return true;
}

SettingsObject::SettingsObject(SettingsManager *settings, MarathonPermissionManager *permissions,
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

SecurityObject::SecurityObject(SecurityManager *security, MarathonPermissionManager *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_security(security)
    , m_factoryReset(new FactoryReset(security, QString::fromLatin1(FactoryReset::SOCKET), this)) {
    Q_ASSERT(m_security);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    QObject::connect(m_factoryReset, &FactoryReset::failed, this, &SecurityObject::EraseFailed);
    QObject::connect(m_security, &SecurityManager::authModeChanged, this,
                     [this]() { emit StateChanged(buildState()); });
    QObject::connect(m_security, &SecurityManager::quickPINChanged, this, [this]() {
        emit QuickPINChanged();
        emit StateChanged(buildState());
    });
    QObject::connect(m_security, &SecurityManager::fingerprintAvailableChanged, this,
                     [this]() { emit StateChanged(buildState()); });
    QObject::connect(m_security, &SecurityManager::lockoutStateChanged, this,
                     [this]() { emit StateChanged(buildState()); });
    QObject::connect(m_security, &SecurityManager::failedAttemptsChanged, this,
                     [this]() { emit StateChanged(buildState()); });
    QObject::connect(m_security, &SecurityManager::dataEncryptionChanged, this,
                     [this]() { emit StateChanged(buildState()); });
    QObject::connect(m_security, &SecurityManager::authenticationFailed, this,
                     [this](const QString &reason) {
                         emit AuthenticationFailed(reason);
                         emit StateChanged(buildState());
                     });
    QObject::connect(m_security, &SecurityManager::authenticationSuccess, this, [this]() {
        emit AuthenticationSuccess();
        emit StateChanged(buildState());
    });
}

QVariantMap SecurityObject::buildState() const {
    return {
        {"authMode", static_cast<int>(m_security->authMode())},
        {"hasQuickPIN", m_security->hasQuickPIN()},
        {"fingerprintAvailable", m_security->fingerprintAvailable()},
        {"isLockedOut", m_security->isLockedOut()},
        {"lockoutSecondsRemaining", m_security->lockoutSecondsRemaining()},
        {"failedAttempts", m_security->failedAttempts()},
        {"canEraseAllContent", m_factoryReset->supported()},
        {"dataEncryption", m_security->dataEncryption()},
    };
}

QVariantMap SecurityObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void SecurityObject::SetQuickPIN(const QString &pin, const QString &systemPassword) {
    if (!requireSystem())
        return;
    m_security->setQuickPIN(pin, systemPassword);
}

void SecurityObject::RemoveQuickPIN(const QString &systemPassword) {
    if (!requireSystem())
        return;
    m_security->removeQuickPIN(systemPassword);
}

void SecurityObject::AuthenticatePassword(const QString &password) {
    if (!requireSystem())
        return;
    m_security->authenticatePassword(password);
}

void SecurityObject::AuthenticateQuickPIN(const QString &pin) {
    // No requireSystem() here — the PIN itself is the auth. The
    // SecurityManager applies its own lockout policy after N failed
    // attempts, and the IpcPermissionedService rate-limit caps the
    // attempt rate at one per RATE_LIMIT_WINDOW_MS. Requiring a separate
    // "system" permission would force every dev/test caller to chain
    // through another permission check that the PIN already represents.
    if (!checkRateLimit(*this, QStringLiteral("Security"))) {
        sendErrorReply(QDBusError::LimitsExceeded, "Rate limit exceeded");
        return;
    }
    m_security->authenticateQuickPIN(pin);
}

void SecurityObject::AuthenticateBiometric(int type) {
    if (!requireSystem())
        return;
    m_security->authenticateBiometric(static_cast<SecurityManager::BiometricType>(type));
}

void SecurityObject::CancelAuthentication() {
    if (!requireSystem())
        return;
    m_security->cancelAuthentication();
}

void SecurityObject::ResetLockout() {
    if (!requireSystem())
        return;
    m_security->resetLockout();
}

bool SecurityObject::IsBiometricEnrolled(int type) {
    if (!requireSystem())
        return false;
    return m_security->isBiometricEnrolled(static_cast<SecurityManager::BiometricType>(type));
}

QString SecurityObject::CurrentUsername() {
    if (!requireSystem())
        return {};
    return m_security->getCurrentUsername();
}

void SecurityObject::EraseAllContent(const QString &secret) {
    if (!requireSystem())
        return;
    m_factoryReset->erase(secret);
}

BluetoothObject::BluetoothObject(BluetoothManager *bt, MarathonPermissionManager *permissions,
                                 AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_bt(bt) {
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

QVariantList BluetoothObject::buildDevices(bool pairedOnly) const {
    QVariantList           out;
    const QList<QObject *> list = pairedOnly ? m_bt->pairedDevices() : m_bt->devices();
    for (QObject *d : list) {
        if (!d)
            continue;
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
    if (!requireBluetooth())
        return {};
    return buildState();
}

void BluetoothObject::SetEnabled(bool enabled) {
    if (!requireBluetooth())
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

DisplayObject::DisplayObject(DisplayManagerCpp *display, FlashlightManagerCpp *flashlight,
                             MarathonPermissionManager *permissions,
                             AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_display(display)
    , m_flashlight(flashlight) {
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
    if (m_flashlight)
        QObject::connect(m_flashlight, &FlashlightManagerCpp::availableChanged, this, push);
}

QVariantMap DisplayObject::buildState() const {
    return {
        {"available", m_display->available()},
        {"autoBrightnessEnabled", m_display->autoBrightnessEnabled()},
        {"rotationLocked", m_display->rotationLocked()},
        {"rotationAvailable", m_display->rotationAvailable()},
        {"lightSensorAvailable", m_display->lightSensorAvailable()},
        {"torchAvailable", m_flashlight && m_flashlight->available()},
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
    // Settings-app slider is a user choice — teach the adaptive curve too.
    m_display->setBrightnessFromUser(brightness);
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
    m_display->setScreenState(on, QStringLiteral("D-Bus Display1.SetScreenState"));
}

void DisplayObject::Wake() {
    // No auth check — turning the screen ON is the equivalent of pressing
    // the hardware power button while the panel is asleep. There's no
    // security exposure: the lock screen / PIN screen still gates anything
    // sensitive, and the rate-limit windowing in IpcPermissionedService
    // prevents wake-spam.
    m_display->setScreenState(true);
}

PowerObject::PowerObject(PowerManagerCpp *power, PowerPolicyController *policy,
                         MarathonPermissionManager *permissions, AppLaunchService *launchService,
                         QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_power(power)
    , m_policy(policy)
    , m_wakeTimers(new WakeTimers(QDBusConnection::sessionBus(), this)) {
    Q_ASSERT(m_power);
    Q_ASSERT(m_policy);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_power, &PowerManagerCpp::batteryLevelChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::isChargingChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::isPluggedInChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::isPowerSaveModeChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::estimatedBatteryTimeChanged, this, push);
    QObject::connect(m_power, &PowerManagerCpp::powerProfileChanged, this, push);
    QObject::connect(m_policy, &PowerPolicyController::dozingChanged, this, push);
}

QVariantMap PowerObject::buildState() const {
    return {
        {"dozing", m_policy->dozing()},
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

bool PowerObject::Wake(const QString &reason) {
    if (!requireSystem())
        return false;
    // Each reason holds a wakelock of that name.
    static const QStringList reasons{QStringLiteral("alarm"), QStringLiteral("call"),
                                     QStringLiteral("notification")};
    if (!reasons.contains(reason)) {
        sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Unknown wake reason"));
        return false;
    }
    qInfo() << "[PowerObject]" << callerAppIdOrEmpty() << "wakes the screen for" << reason;
    m_policy->wake(reason);
    return true;
}

bool PowerObject::ScheduleWake(qint64 epochSecs, const QString &reason) {
    if (!requireSystem())
        return false;
    if (epochSecs <= QDateTime::currentSecsSinceEpoch()) {
        sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Wake time is not in the future"));
        return false;
    }
    const QString app = callerAppIdOrEmpty();
    qInfo() << "[PowerObject]" << app << "schedules a wake-up at" << epochSecs << "for" << reason;
    // Answered once systemd has the timer.
    setDelayedReply(true);
    m_wakeTimers->set(
        QStringLiteral("app-") + app, epochSecs,
        [bus = connection(), call = message()](bool ok) { bus.send(call.createReply(ok)); });
    return false;
}

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
    : IpcPermissionedService(permissions, launchService, parent)
    , m_audio(audio)
    , m_policy(policy) {
    Q_ASSERT(m_audio);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);

    auto push = [this]() { emit StateChanged(buildState()); };
    QObject::connect(m_audio, &AudioManagerCpp::availableChanged, this, push);
    QObject::connect(m_audio, &AudioManagerCpp::volumeChanged, this, push);
    QObject::connect(m_audio, &AudioManagerCpp::mutedChanged, this, push);
    QObject::connect(m_audio, &AudioManagerCpp::streamsChanged, this, push);
    if (m_policy) {
        QObject::connect(m_policy, &AudioPolicyController::audioProfileChanged, this, push);
        QObject::connect(m_policy, &AudioPolicyController::doNotDisturbChanged, this, push);
    }
}

QVariantMap AudioObject::buildState() const {
    return {
        {"available", m_audio->available()},
        {"volume", m_audio->volume()},
        {"muted", m_audio->muted()},
        {"perAppVolumeSupported", m_audio->perAppVolumeSupported()},
        {"streams", audioStreamsToVariantList(m_audio)},
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

NetworkObject::NetworkObject(NetworkManagerCpp *network, MarathonPermissionManager *permissions,
                             AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_network(network) {
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
    QObject::connect(m_network, &NetworkManagerCpp::hotspotActiveChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::airplaneModeEnabledChanged, this, push);
    QObject::connect(m_network, &NetworkManagerCpp::availableNetworksChanged, this, push);

    QObject::connect(m_network, &NetworkManagerCpp::networkError, this,
                     &NetworkObject::NetworkError);
    QObject::connect(m_network, &NetworkManagerCpp::connectionSuccess, this,
                     &NetworkObject::ConnectionSuccess);
    QObject::connect(m_network, &NetworkManagerCpp::connectionFailed, this,
                     &NetworkObject::ConnectionFailed);
}

QVariantMap NetworkObject::buildState() const {
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

void NetworkObject::ConnectToHiddenNetwork(const QString &ssid, const QString &security,
                                           const QString &password) {
    if (!requireNetwork())
        return;
    m_network->connectToHiddenNetwork(ssid, security, password);
}

void NetworkObject::ForgetNetwork(const QString &ssid) {
    if (!requireNetwork())
        return;
    m_network->forgetNetwork(ssid);
}

ModemObject::ModemObject(ModemManagerCpp *modem, MarathonPermissionManager *permissions,
                         AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_modem(modem) {
    Q_ASSERT(m_modem);
    auto push = [this]() { emit StateChanged(buildState()); };
    for (auto signal : {&ModemManagerCpp::modemAvailableChanged,
                        &ModemManagerCpp::modemEnabledChanged, &ModemManagerCpp::simPresentChanged,
                        &ModemManagerCpp::registeredChanged, &ModemManagerCpp::operatorNameChanged,
                        &ModemManagerCpp::signalStrengthChanged,
                        &ModemManagerCpp::networkTypeChanged, &ModemManagerCpp::roamingChanged,
                        &ModemManagerCpp::dataEnabledChanged,
                        &ModemManagerCpp::dataRoamingAllowedChanged,
                        &ModemManagerCpp::modesChanged})
        // clazy can't resolve a member-function pointer held in a variable.
        QObject::connect(m_modem, signal, this, push); // clazy:exclude=connect-non-signal
}

QVariantMap ModemObject::buildState() const {
    return {
        {"available", m_modem->modemAvailable()},
        {"enabled", m_modem->modemEnabled()},
        {"simPresent", m_modem->simPresent()},
        {"registered", m_modem->registered()},
        {"operatorName", m_modem->operatorName()},
        {"signalStrength", m_modem->signalStrength()},
        {"networkType", m_modem->networkType()},
        {"roaming", m_modem->roaming()},
        {"dataEnabled", m_modem->dataEnabled()},
        {"dataRoamingAllowed", m_modem->dataRoamingAllowed()},
        {"supportedModes", m_modem->supportedModes()},
        {"allowedModes", m_modem->allowedModes()},
    };
}

QVariantMap ModemObject::GetState() {
    if (!requireNetwork())
        return {};
    return buildState();
}

void ModemObject::EnableData() {
    if (requireNetwork())
        m_modem->enableData();
}

void ModemObject::DisableData() {
    if (requireNetwork())
        m_modem->disableData();
}

void ModemObject::SetDataRoamingAllowed(bool allowed) {
    if (requireNetwork())
        m_modem->setDataRoamingAllowed(allowed);
}

void ModemObject::SetAllowedModes(uint allowed) {
    if (requireNetwork())
        m_modem->setAllowedModes(allowed);
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
    if (!const_cast<NetworkObject *>(this)->requireNetwork())
        return false;
    return m_network->isHotspotActive();
}

MediaLibraryObject::MediaLibraryObject(MediaLibraryManager       *media,
                                       MarathonPermissionManager *permissions,
                                       AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_media(media) {
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

PermissionsObject::PermissionsObject(MarathonPermissionManager *permissions,
                                     AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent) {
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_permissions, &MarathonPermissionManager::permissionGranted, this,
                     &PermissionsObject::PermissionGranted);
    QObject::connect(m_permissions, &MarathonPermissionManager::permissionDenied, this,
                     &PermissionsObject::PermissionDenied);
    QObject::connect(m_permissions, &MarathonPermissionManager::permissionRequested, this,
                     &PermissionsObject::PermissionRequested);
}

// MARATHON_TEST_TRUSTED ($MARATHON_TEST_CALLER_ID) is admitted as the synthetic
// admin caller, only when the test-bypass env var is set.
static bool authorizePermissionCall(const QString &caller, const QString &targetAppId,
                                    PermissionAuth::Op op) {
    if (g_testBypassEnabled && caller == QLatin1String(MARATHON_TEST_CALLER_ID))
        return true;
    return PermissionAuth::allowed(caller, targetAppId, op);
}

bool PermissionsObject::HasPermission(const QString &appId, const QString &permission) {
    const QString caller = callerAppIdOrEmpty();
    if (!authorizePermissionCall(caller, appId, PermissionAuth::Op::Read)) {
        sendErrorReply(QDBusError::AccessDenied, "AppId spoofing or unknown caller");
        return false;
    }
    return m_permissions->hasPermission(appId, permission);
}

void PermissionsObject::RequestPermission(const QString &appId, const QString &permission) {
    const QString caller = callerAppIdOrEmpty();
    if (!authorizePermissionCall(caller, appId, PermissionAuth::Op::Request)) {
        sendErrorReply(QDBusError::AccessDenied, "AppId spoofing or unknown caller");
        return;
    }
    m_permissions->requestPermission(appId, permission);
}

void PermissionsObject::SetPermission(const QString &appId, const QString &permission, bool granted,
                                      bool remember) {
    const QString caller = callerAppIdOrEmpty();
    if (!authorizePermissionCall(caller, appId,
                                 granted ? PermissionAuth::Op::Grant : PermissionAuth::Op::Revoke)) {
        sendErrorReply(QDBusError::AccessDenied, "AppId spoofing or unknown caller");
        return;
    }
    m_permissions->setPermission(appId, permission, granted, remember);
}

// The declared session service allowed to prompt for Android apps, or "".
QString PermissionsObject::requireForeignPrompter() {
    const QString caller = callerAppIdOrEmpty();
    if ((g_testBypassEnabled && caller == QLatin1String(MARATHON_TEST_CALLER_ID)) ||
        ServiceCaller::allowed(caller, {PermissionAuth::kForeignPrompts}))
        return caller;
    sendErrorReply(QDBusError::AccessDenied, "Not a permission prompter");
    return {};
}

QVariantMap PermissionsObject::PromptAndroid(const QString &appId, const QString &permission,
                                             const QVariantMap &options) {
    static const QRegularExpression requestId(QStringLiteral("^[0-9a-f]{16}$"));
    static constexpr int            kMaxWaiting = 16;
    const QString                   caller      = requireForeignPrompter();
    if (caller.isEmpty())
        return {};
    const QString request = options.value(QStringLiteral("request")).toString();
    QVariantMap   cleaned;
    const auto    vocabulary = MarathonManifest::permissions();
    const bool    known      = std::any_of(vocabulary.cbegin(), vocabulary.cend(),
                                           [&](const MarathonManifest::Permission &p) {
                                       return p.name == permission && !p.restricted;
                                           });
    if (!PermissionAuth::isAndroidAppId(appId) || !known || !requestId.match(request).hasMatch() ||
        !PermissionAuth::foreignOptions(options, &cleaned)) {
        sendErrorReply(QDBusError::InvalidArgs, "Bad prompt");
        return {};
    }
    const QString key = caller + QLatin1Char(' ') + request;
    if (m_waiting.contains(key) || m_waiting.size() >= kMaxWaiting) {
        sendErrorReply(QDBusError::LimitsExceeded, "Too many prompts");
        return {};
    }
    m_waiting.insert(key);
    setDelayedReply(true);
    const QDBusMessage call = message();
    QDBusConnection    bus  = connection();
    // A prompter that leaves the bus takes its prompts with it.
    auto *gone = new QDBusServiceWatcher(call.service(), bus,
                                         QDBusServiceWatcher::WatchForUnregistration, this);
    connect(gone, &QDBusServiceWatcher::serviceUnregistered, this,
            [this, key] { m_permissions->cancelForeign(key); });
    QPointer<PermissionsObject>   self(this);
    QPointer<QDBusServiceWatcher> watcher(gone);
    m_permissions->askForeign(
        key, appId, permission, cleaned,
        [self, watcher, key, call, bus](const QString &answer, bool precise) mutable {
            if (self)
                self->m_waiting.remove(key);
            if (watcher)
                watcher->deleteLater();
            bus.send(call.createReply(QVariant(QVariantMap{{QStringLiteral("answer"), answer},
                                                           {QStringLiteral("precise"), precise}})));
        });
    return {};
}

void PermissionsObject::CancelAndroidPrompt(const QString &request) {
    const QString caller = requireForeignPrompter();
    if (!caller.isEmpty())
        m_permissions->cancelForeign(caller + QLatin1Char(' ') + request);
}

ContactsObject::ContactsObject(ContactsManager *contacts, MarathonPermissionManager *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_contacts(contacts) {
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

CallHistoryObject::CallHistoryObject(CallHistoryManager        *callHistory,
                                     MarathonPermissionManager *permissions,
                                     AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_callHistory(callHistory) {
    Q_ASSERT(m_callHistory);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_callHistory, &CallHistoryManager::historyChanged, this,
                     &CallHistoryObject::HistoryChanged);
    QObject::connect(m_callHistory, &CallHistoryManager::callAdded, this,
                     &CallHistoryObject::CallAdded);
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

TelephonyObject::TelephonyObject(TelephonyService          *telephony,
                                 MarathonPermissionManager *permissions,
                                 AppLaunchService *launchService, AudioRoutingManager *audioRouting,
                                 QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_telephony(telephony)
    , m_audioRouting(audioRouting) {
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

QString TelephonyObject::CallState() const {
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

void TelephonyObject::SimulateIncomingCall(const QString &number) {
    if (!requirePhone())
        return;
    m_telephony->simulateIncomingCall(number);
}

void TelephonyObject::SimulateCallStateChange(const QString &state) {
    if (!requirePhone())
        return;
    m_telephony->simulateCallStateChange(state);
}

void TelephonyObject::SetSpeakerphone(bool on) {
    if (!requirePhone())
        return;
    if (m_audioRouting)
        m_audioRouting->setSpeakerphone(on);
}

void TelephonyObject::SetCallMuted(bool muted) {
    if (!requirePhone())
        return;
    if (m_audioRouting)
        m_audioRouting->setMuted(muted);
}

bool TelephonyObject::IsSpeakerphoneOn() const {
    if (!const_cast<TelephonyObject *>(this)->requirePhone())
        return false;
    return m_audioRouting ? m_audioRouting->isSpeakerphoneEnabled() : false;
}

bool TelephonyObject::IsCallMuted() const {
    if (!const_cast<TelephonyObject *>(this)->requirePhone())
        return false;
    return m_audioRouting ? m_audioRouting->isMuted() : false;
}

SmsObject::SmsObject(SMSService *sms, MarathonPermissionManager *permissions,
                     AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_sms(sms) {
    Q_ASSERT(m_sms);
    Q_ASSERT(m_permissions);
    Q_ASSERT(m_launchService);
    QObject::connect(m_sms, &SMSService::messageReceived, this, &SmsObject::MessageReceived);
    QObject::connect(m_sms, &SMSService::messageSent, this, &SmsObject::MessageSent);
    QObject::connect(m_sms, &SMSService::sendFailed, this, &SmsObject::SendFailed);
    QObject::connect(m_sms, &SMSService::conversationsChanged, this,
                     &SmsObject::ConversationsChanged);
    QObject::connect(m_sms, &SMSService::messageStatusChanged, this,
                     &SmsObject::MessageStatusChanged);
    QObject::connect(m_sms, &SMSService::mmsAvailableChanged, this,
                     &SmsObject::MmsAvailableChanged);
    if (MmsManager *mms = m_sms->mmsManager()) {
        QObject::connect(mms, &MmsManager::settingsChanged, this, &SmsObject::MmsSettingsChanged);
        QObject::connect(mms, &MmsManager::bearerError, this, &SmsObject::MmsBearerError);
    }
    qDBusRegisterMetaType<MmsPartArg>();
    qDBusRegisterMetaType<QList<MmsPartArg>>();
}

int SmsObject::SendMms(const QStringList &recipients, const QString &text,
                       const QList<MmsPartArg> &parts) {
    if (!requireSms())
        return -1;
    constexpr int kMaxRecipients = 20;
    constexpr int kMaxParts      = 25;
    if (recipients.isEmpty() || recipients.size() > kMaxRecipients || parts.size() > kMaxParts) {
        sendErrorReply(QDBusError::InvalidArgs, "1 to 20 recipients and at most 25 parts");
        return -1;
    }
    QList<MmsPart> list;
    for (const MmsPartArg &part : parts) {
        if (!part.fd.isValid() || part.contentType.isEmpty()) {
            sendErrorReply(QDBusError::InvalidArgs, "Each part needs a type and a descriptor");
            return -1;
        }
        list << MmsPart{part.contentType, part.name, part.fd.fileDescriptor()};
    }
    return m_sms->sendMms(recipients, text, list);
}

QDBusUnixFileDescriptor SmsObject::OpenAttachment(int id) {
    if (!requireSms())
        return {};
    const QString path = m_sms->attachmentPath(id);
    const int     fd   = path.isEmpty() ? -1 : ::open(QFile::encodeName(path).constData(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        sendErrorReply(QDBusError::InvalidArgs, "No such attachment");
        return {};
    }
    QDBusUnixFileDescriptor out(fd);
    ::close(fd);
    return out;
}

bool SmsObject::IsMmsAvailable() {
    return requireSms() && m_sms->mmsAvailable();
}

QVariantMap SmsObject::GetMmsSettings() {
    if (!requireMmsSettings())
        return {};
    MmsManager *mms = m_sms->mmsManager();
    if (!mms)
        return {};
    setDelayedReply(true);
    const QDBusMessage call = message();
    mms->viewSettings(this, [call](const QVariantMap &settings) {
        QDBusConnection::sessionBus().send(call.createReply(QVariant(settings)));
    });
    return {};
}

void SmsObject::SetMmsSettings(const QVariantMap &values) {
    if (!requireMmsSettings())
        return;
    MmsManager *mms = m_sms->mmsManager();
    if (!mms) {
        sendErrorReply(QDBusError::NotSupported, "MMS isn't available");
        return;
    }
    setDelayedReply(true);
    const QDBusMessage call = message();
    mms->changeSettings(values, this, [this, call, values](const QString &error) {
        if (error.isEmpty()) {
            QDBusConnection::sessionBus().send(call.createReply());
            emit MmsSettingsChanged(values);
        } else {
            QDBusConnection::sessionBus().send(call.createErrorReply(QDBusError::InvalidArgs, error));
        }
    });
}

QVariantList SmsObject::GetConversations() {
    if (!requireSms())
        return {};
    const QVariantList list = m_sms->conversations();
    qDebug() << "[SmsObject] GetConversations -> caller=" << callerAppIdOrEmpty()
             << "count=" << list.size();
    return list;
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

bool SmsObject::DeleteMessage(int id) {
    if (!requireSms())
        return false;
    return m_sms->deleteMessage(id);
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

void SmsObject::SimulateIncomingSMS(const QString &sender, const QString &message) {
    if (!requireSms())
        return;
    m_sms->simulateIncomingSMS(sender, message);
}

NavigationObject::NavigationObject(AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_launchService(launchService) {
    Q_ASSERT(m_launchService);
    connect(m_launchService, &AppLaunchService::routeForRunningApp, this,
            &NavigationObject::DeepLinkRequested);
}

QString NavigationObject::callerAppIdOrEmpty() const {
    return dbusCallerAppIdOrEmpty(*this, m_launchService);
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
    if (callerAppIdOrEmpty().startsWith(ServiceCaller::kPrefix))
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
    if (!callerAppIdOrEmpty().startsWith(ServiceCaller::kPrefix)) {
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

HapticObject::HapticObject(HapticManager *haptic, AppLaunchService *launchService, QObject *parent)
    : QObject(parent)
    , m_haptic(haptic)
    , m_launchService(launchService) {
    Q_ASSERT(m_haptic);
}

bool HapticObject::IsAvailable() const {
    return m_haptic ? m_haptic->available() : false;
}

void HapticObject::Light() {
    if (m_haptic && m_haptic->available())
        m_haptic->vibrate(10);
}

void HapticObject::Medium() {
    if (m_haptic && m_haptic->available())
        m_haptic->vibrate(25);
}

void HapticObject::Heavy() {
    if (m_haptic && m_haptic->available())
        m_haptic->vibrate(50);
}

void HapticObject::Vibrate(int duration) {
    if (m_haptic && m_haptic->available())
        m_haptic->vibrate(duration);
}

void HapticObject::VibratePattern(const QVariantList &pattern) {
    if (m_haptic && m_haptic->available())
        m_haptic->vibratePatternVariant(pattern);
}

void HapticObject::Stop() {
    if (m_haptic)
        m_haptic->cancelVibration();
}

SensorObject::SensorObject(SensorManagerCpp *sensors, MarathonPermissionManager *permissions,
                           AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_sensors(sensors) {
    Q_ASSERT(m_sensors);
    QObject::connect(m_sensors, &SensorManagerCpp::proximityNearChanged, this,
                     [this]() { emit ProximityChanged(m_sensors->proximityNear()); });
    QObject::connect(m_sensors, &SensorManagerCpp::ambientLightChanged, this,
                     [this]() { emit AmbientLightChanged(m_sensors->ambientLight()); });
}

bool SensorObject::IsAvailable() {
    return requireSensors() && m_sensors->available();
}

bool SensorObject::ProximityNear() {
    return requireSensors() && m_sensors->proximityNear();
}

int SensorObject::AmbientLight() {
    return requireSensors() ? m_sensors->ambientLight() : 0;
}

LocationObject::LocationObject(LocationManager *location, MarathonPermissionManager *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_location(location) {
    Q_ASSERT(m_location);
    QObject::connect(m_location, &LocationManager::locationChanged, this,
                     [this]() { emit LocationChanged(this->location()); });
    QObject::connect(m_location, &LocationManager::activeChanged, this,
                     [this]() { emit activeChanged(m_location->active()); });
}

bool LocationObject::IsAvailable() {
    return requireLocation() && m_location->available();
}

bool LocationObject::IsActive() {
    return requireLocation() && m_location->active();
}

void LocationObject::Start() {
    if (requireLocation())
        m_location->start();
}

void LocationObject::Stop() {
    if (requireLocation())
        m_location->stop();
}

QVariantMap LocationObject::location() const {
    return {{"latitude", m_location->latitude()},   {"longitude", m_location->longitude()},
            {"accuracy", m_location->accuracy()},   {"altitude", m_location->altitude()},
            {"speed", m_location->speed()},         {"heading", m_location->heading()},
            {"timestamp", m_location->timestamp()}};
}

QVariantMap LocationObject::GetLocation() {
    return requireLocation() ? location() : QVariantMap();
}

AlarmObject::AlarmObject(AlarmManagerCpp *alarms, MarathonPermissionManager *permissions,
                         AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_alarms(alarms) {
    Q_ASSERT(m_alarms);
    connect(m_alarms, &AlarmManagerCpp::alarmsChanged, this, &AlarmObject::AlarmsChanged);
    connect(m_alarms, &AlarmManagerCpp::activeAlarmsChanged, this,
            &AlarmObject::ActiveAlarmsChanged);
    connect(m_alarms, &AlarmManagerCpp::alarmTriggered, this, &AlarmObject::AlarmTriggered);
    connect(m_alarms, &AlarmManagerCpp::alarmDismissed, this, &AlarmObject::AlarmDismissed);
    connect(m_alarms, &AlarmManagerCpp::alarmSnoozed, this, &AlarmObject::AlarmSnoozed);
}

QVariantList AlarmObject::GetAlarms() {
    return requireAlarms() ? m_alarms->alarms() : QVariantList();
}

QVariantList AlarmObject::GetActiveAlarms() {
    return requireAlarms() ? m_alarms->activeAlarms() : QVariantList();
}

QString AlarmObject::CreateAlarm(const QString &time, const QString &label,
                                 const QList<int> &repeat, const QVariantMap &options) {
    return requireAlarms() ? m_alarms->createAlarm(time, label, repeat, options) : QString();
}

bool AlarmObject::UpdateAlarm(const QString &id, const QVariantMap &updates) {
    return requireAlarms() && m_alarms->updateAlarm(id, normalizeMapDeep(updates));
}

bool AlarmObject::DeleteAlarm(const QString &id) {
    return requireAlarms() && m_alarms->deleteAlarm(id);
}

bool AlarmObject::EnableAlarm(const QString &id) {
    return requireAlarms() && m_alarms->enableAlarm(id);
}

bool AlarmObject::DisableAlarm(const QString &id) {
    return requireAlarms() && m_alarms->disableAlarm(id);
}

bool AlarmObject::SnoozeAlarm(const QString &id) {
    return requireAlarms() && m_alarms->snoozeAlarm(id);
}

bool AlarmObject::DismissAlarm(const QString &id) {
    return requireAlarms() && m_alarms->dismissAlarm(id);
}

void AlarmObject::StopAll() {
    if (requireAlarms())
        m_alarms->stopAll();
}

void AlarmObject::TriggerAlarmNow(const QString &label) {
    if (requireAlarms())
        m_alarms->triggerAlarmNow(label);
}

// === UpdatesObject =========================================================

UpdatesObject::UpdatesObject(UpdateService *updates, MarathonPermissionManager *permissions,
                             AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_updates(updates) {
    connect(m_updates, &UpdateService::stateChanged, this,
            [this]() { emit StateChanged(buildState()); });
}

QVariantMap UpdatesObject::buildState() const {
    return {
        {"state", m_updates->stateName()},
        {"currentVersion", m_updates->currentVersion()},
        {"osVersion", m_updates->osVersion()},
        {"availableVersion", m_updates->availableVersion()},
        {"downloadSize", m_updates->downloadSize()},
        {"releaseNotes", m_updates->releaseNotes()},
        {"progress", m_updates->progress()},
        {"blockedReason", m_updates->blockedReason()},
        {"rolledBackVersion", m_updates->rolledBackVersion()},
        {"lastError", m_updates->lastError()},
        {"lastCheckedMs", m_updates->lastCheckedMs()},
        {"autoUpdate", m_updates->autoUpdate()},
        {"restartScheduled", m_updates->restartScheduled()},
        {"currentReleaseNotes", m_updates->currentReleaseNotes()},
    };
}

QVariantMap UpdatesObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void UpdatesObject::CheckNow() {
    if (requireSystem())
        m_updates->checkNow();
}

void UpdatesObject::Install() {
    if (requireSystem())
        m_updates->install();
}

void UpdatesObject::Cancel() {
    if (requireSystem())
        m_updates->cancel();
}

void UpdatesObject::Reboot() {
    if (requireSystem())
        m_updates->reboot();
}

void UpdatesObject::ScheduleRestart() {
    if (requireSystem())
        m_updates->scheduleRestart();
}

void UpdatesObject::SetAutoUpdate(bool on) {
    if (requireSystem())
        m_updates->setAutoUpdate(on);
}

// === DavObject =============================================================

DavObject::DavObject(DavSyncEngine *engine, MarathonPermissionManager *permissions,
                     AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_engine(engine) {
    if (m_engine) {
        connect(m_engine, &DavSyncEngine::accountsChanged, this,
                [this]() { emit AccountsChanged(); });
        connect(m_engine, &DavSyncEngine::syncFinished, this,
                [this](const QString &accountId, int, int, int) { emit SyncFinished(accountId); });
        connect(m_engine, &DavSyncEngine::accountDiscovered, this, &DavObject::AccountDiscovered);
        connect(m_engine, &DavSyncEngine::accountDiscoveryFailed, this,
                &DavObject::AccountDiscoveryFailed);
    }
}

QVariantList DavObject::ListAccounts() {
    if (!requireSystem())
        return {};
    return m_engine ? m_engine->listAccounts() : QVariantList{};
}

QString DavObject::AddAccount(const QString &displayName, const QString &baseUrl,
                              const QString &username, const QString &secret,
                              const QString &authKind) {
    if (!requireSystem())
        return {};
    return m_engine ? m_engine->addAccount(displayName, baseUrl, username, secret, authKind) :
                      QString{};
}

bool DavObject::RemoveAccount(const QString &id) {
    if (!requireSystem())
        return false;
    return m_engine ? m_engine->removeAccount(id) : false;
}

void DavObject::EnableAccount(const QString &id, bool enabled) {
    if (!requireSystem())
        return;
    if (m_engine)
        m_engine->enableAccount(id, enabled);
}

void DavObject::SyncNow() {
    if (!requireSystem())
        return;
    if (m_engine)
        m_engine->syncNow();
}

QVariantMap DavObject::GetState() {
    if (!requireSystem())
        return {};
    if (!m_engine)
        return {};
    return {
        {"accountCount", m_engine->accountCount()},
        {"syncing", m_engine->syncing()},
        {"lastError", m_engine->lastError()},
        {"lastSyncMs", m_engine->lastSyncMs()},
    };
}

// === AppStoreObject ========================================================
//
// Thin DBus passthrough to MarathonAppStoreService — the shell holds the
// service so the catalog cache, network access manager, and download
// machinery all stay in one process while the Store app (running in
// app-runner) reads via IPC. State change signals re-broadcast catalog
// load + download progress so the Store's UI can stay live.

AppStoreObject::AppStoreObject(MarathonAppStoreService *appStore, MarathonAppInstaller *installer,
                               MarathonPermissionManager *permissions,
                               AppLaunchService *launchService, QObject *parent)
    : IpcPermissionedService(permissions, launchService, parent)
    , m_appStore(appStore)
    , m_installer(installer) {
    if (m_appStore) {
        connect(m_appStore, &MarathonAppStoreService::catalogLoadedChanged, this,
                [this]() { emit StateChanged(buildState()); });
        connect(m_appStore, &MarathonAppStoreService::loadingChanged, this,
                [this]() { emit StateChanged(buildState()); });
        connect(m_appStore, &MarathonAppStoreService::catalogRefreshed, this,
                [this]() { emit CatalogRefreshed(); });
        connect(m_appStore, &MarathonAppStoreService::downloadProgress, this,
                &AppStoreObject::DownloadProgress);
        connect(m_appStore, &MarathonAppStoreService::downloadComplete, this,
                &AppStoreObject::DownloadComplete);
        connect(m_appStore, &MarathonAppStoreService::downloadFailed, this,
                &AppStoreObject::DownloadFailed);
    }
    if (m_installer) {
        connect(m_installer, &MarathonAppInstaller::uninstallComplete, this,
                &AppStoreObject::UninstallComplete);
        connect(m_installer, &MarathonAppInstaller::uninstallFailed, this,
                &AppStoreObject::UninstallFailed);
    }
}

QVariantMap AppStoreObject::buildState() const {
    if (!m_appStore)
        return {};
    return {
        {"catalogLoaded", m_appStore->catalogLoaded()},
        {"loading", m_appStore->loading()},
        {"repositoryUrl", m_appStore->repositoryUrl()},
    };
}

QVariantMap AppStoreObject::GetState() {
    if (!requireSystem())
        return {};
    return buildState();
}

void AppStoreObject::RefreshCatalog() {
    if (!requireSystem())
        return;
    if (m_appStore)
        m_appStore->refreshCatalog();
}

QVariantList AppStoreObject::SearchApps(const QString &query) {
    if (!requireSystem())
        return {};
    return m_appStore ? m_appStore->searchApps(query) : QVariantList{};
}

QVariantMap AppStoreObject::GetApp(const QString &appId) {
    if (!requireSystem())
        return {};
    return m_appStore ? m_appStore->getApp(appId) : QVariantMap{};
}

QVariantList AppStoreObject::GetFeaturedApps() {
    if (!requireSystem())
        return {};
    return m_appStore ? m_appStore->getFeaturedApps() : QVariantList{};
}

QVariantList AppStoreObject::GetAppsByCategory(const QString &category) {
    if (!requireSystem())
        return {};
    return m_appStore ? m_appStore->getAppsByCategory(category) : QVariantList{};
}

QVariantList AppStoreObject::GetAvailableUpdates() {
    if (!requireSystem())
        return {};
    return m_appStore ? m_appStore->getAvailableUpdates() : QVariantList{};
}

void AppStoreObject::CheckForUpdates() {
    if (!requireSystem())
        return;
    if (m_appStore)
        m_appStore->checkForUpdates();
}

void AppStoreObject::DownloadApp(const QString &appId) {
    if (!requireSystem())
        return;
    if (m_appStore)
        m_appStore->downloadApp(appId);
}

void AppStoreObject::CancelDownload(const QString &appId) {
    if (!requireSystem())
        return;
    if (m_appStore)
        m_appStore->cancelDownload(appId);
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
    const QString appId = dbusCallerAppIdOrEmpty(*this, m_launchService);
    if (appId.isEmpty()) {
        sendErrorReply(QDBusError::AccessDenied, "Unknown caller");
        return 0;
    }
    // Manifest gate: the app must have declared this category at install
    // time. Apps can't widen their privileges at runtime.
    const QStringList declared = m_appRegistry->getBackgroundCapabilities(appId);
    if (!declared.contains(category)) {
        SecurityLogger::logPermissionDenied(appId, "background:" + category);
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
    const QString appId = dbusCallerAppIdOrEmpty(*this, m_launchService);
    if (appId.isEmpty())
        return {};
    return m_lifecycle->activeCapabilities(appId);
}

AmbienceObject::AmbienceObject(AmbienceService *ambience, QObject *parent)
    : QObject(parent)
    , m_ambience(ambience) {
    connect(ambience, &AmbienceService::ambienceChanged, this, &AmbienceObject::AmbienceChanged);
}

QVariantMap AmbienceObject::GetAmbience() {
    return m_ambience->ambience();
}

WallpaperObject::WallpaperObject(WallpaperStore *store, QObject *parent)
    : QObject(parent)
    , m_store(store) {}

QVariantList WallpaperObject::GetWallpapers() {
    return m_store->wallpapers();
}
