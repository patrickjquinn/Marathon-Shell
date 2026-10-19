#include "settingsmanager.h"
#include "deviceprofile.h"
#include "soundname.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJSEngine>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QTimer>
#include <QTimeZone>
#include <QUrl>

#include <algorithm>
#include <ctime>

SettingsManager *SettingsManager::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new SettingsManager(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("marathon-os", "Marathon Shell")
    , m_userScaleFactor(1.0)
    , m_wallpaperPath("qrc:/wallpapers/meridian.jpg")
    , m_deviceName("Marathon OS")
    , m_autoLock(true)
    , m_autoLockTimeout(0)
    , m_showNotificationPreviews(true)
    , m_timeFormat("12h")
    , m_dateFormat("US")
    , m_ringtone("qrc:/sounds/resources/sounds/phone/bbpro1.wav")
    , m_notificationSound("qrc:/sounds/resources/sounds/text/chime.wav")
    , m_alarmSound("qrc:/sounds/resources/sounds/alarms/alarm_sunrise.wav")
    , m_mediaVolume(0.6)
    , m_ringtoneVolume(0.8)
    , m_alarmVolume(0.9)
    , m_notificationVolume(0.7)
    , m_systemVolume(0.5)
    , m_dndEnabled(false)
    , m_vibrationEnabled(true)
    , m_audioProfile("normal")
    , m_screenTimeout(300000)
    , m_autoBrightness(false)
    , m_statusBarClockPosition("center")
    , m_showNotificationsOnLockScreen(true)
    // Default ON: the consumer home grid should not surface terminals,
    // foot servers, htop, marathon-test etc. The DesktopFileParser ships
    // an explicit kHiddenDevTools deny-list + an X-Purism/X-KDE/Mobile
    // form-factor allowlist; both only kick in when this gate is true.
    // Users with a developer leaning can toggle the gate off in Settings
    // → Apps and get the full freedesktop list back.
    , m_filterMobileFriendlyApps(true)
    , m_appSortOrder("alphabetical")
    , m_appGridColumns(0)
    , m_searchNativeApps(true)
    , m_showNotificationBadges(true)
    , m_showFrequentApps(false)
    , m_firstRunComplete(false)
    , m_keyboardAutoCorrection(true)
    , m_keyboardAutoCapitalize(true)
    , m_keyboardPredictiveText(true)
    , m_keyboardHapticStrength("medium")
    , m_keyboardLanguage("en_US")
    , m_unifiedPushFallbackEnabled(false) {
    m_flushTimer.setSingleShot(true);
    m_flushTimer.setInterval(500);
    connect(&m_flushTimer, &QTimer::timeout, this, &SettingsManager::flush);
    load();
    watchTimedate();

    // Watch the conf file for external changes (Settings app process writes,
    // OOBE writes, etc) and live-reload so the shell reflects them without
    // a restart. The Settings app runs as a separate marathon-app-runner
    // process — it pokes QSettings into the same file but the shell's
    // SettingsManager only sees that file if we watch it.
    m_watcher          = new QFileSystemWatcher(this);
    const QString path = m_settings.fileName();
    if (!path.isEmpty() && QFileInfo::exists(path)) {
        m_watcher->addPath(path);
    }
    // Also watch the parent dir — some editors rewrite the file (delete +
    // create) and the watcher loses the original inode; re-adding the path
    // when the dir notifies gets us back on track.
    const QString dir = QFileInfo(path).absolutePath();
    if (!dir.isEmpty()) {
        m_watcher->addPath(dir);
    }
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this,
            &SettingsManager::onSettingsFileChanged);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this, path](const QString &) {
        // Re-arm: if the watched file got swapped via rename, the path
        // disappears from m_watcher->files(). Add it back.
        if (QFileInfo::exists(path) && !m_watcher->files().contains(path)) {
            m_watcher->addPath(path);
            onSettingsFileChanged(path);
        }
    });
}

void SettingsManager::onSettingsFileChanged(const QString &path) {
    // Guard against echoing our own writes back through load().
    if (m_inSelfWrite) {
        return;
    }
    // Debounce — QFileSystemWatcher may fire multiple times for a single
    // logical write (QSettings does write-temp + rename). 50 ms is enough
    // to coalesce the burst without making Settings UI feel sluggish.
    QTimer::singleShot(50, this, [this, path]() {
        m_settings.sync();
        const qreal   prevScale = m_userScaleFactor;
        const QString prevWp    = m_wallpaperPath;
        const bool    prevRm    = m_reduceMotion;
        load();
        // Re-add the path in case the rename invalidated the watch handle.
        if (m_watcher && !m_watcher->files().contains(path) && QFileInfo::exists(path)) {
            m_watcher->addPath(path);
        }
        // Emit only the properties that actually changed so QML re-bindings
        // don't churn unnecessarily.
        if (!qFuzzyCompare(prevScale, m_userScaleFactor)) {
            qInfo() << "[SettingsManager] external write: userScaleFactor" << prevScale << "->"
                    << m_userScaleFactor;
            emit userScaleFactorChanged();
        }
        if (prevWp != m_wallpaperPath) {
            emit wallpaperPathChanged();
        }
        if (prevRm != m_reduceMotion) {
            emit reduceMotionChanged();
        }
    });
}

namespace {
    QString defaultSystemDataDir() {
        return "/usr/share/marathon-shell";
    }

    QString dataDirFromEnvOrDefault() {
        const QByteArray env = qgetenv("MARATHON_DATA_DIR").trimmed();
        if (!env.isEmpty()) {
            return QString::fromLocal8Bit(env);
        }
        QString sys = defaultSystemDataDir();
        if (QDir(sys).exists())
            return sys;

        const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
        QString       user = home + "/.local/share/marathon-shell";
        if (QDir(user).exists())
            return user;

        return {};
    }

    QString toFileUrlIfExists(const QString &absolutePath) {
        if (absolutePath.isEmpty())
            return {};
        if (!QFileInfo::exists(absolutePath))
            return {};
        return QUrl::fromLocalFile(absolutePath).toString();
    }

    QString qrcFallbackForRelative(const QString &relativePath) {
        if (relativePath.startsWith("wallpapers/")) {
            return "qrc:/wallpapers/" + relativePath.mid(QString("wallpapers/").size());
        }
        if (relativePath.startsWith("sounds/")) {

            return "qrc:/sounds/resources/sounds/" + relativePath.mid(QString("sounds/").size());
        }
        return {};
    }

    QString migrateQrcToFile(const QString &pathOrUrl, const QString &dataDir) {

        if (dataDir.isEmpty())
            return pathOrUrl;

        const QString wpPrefix = "qrc:/wallpapers/";
        if (pathOrUrl.startsWith(wpPrefix)) {
            const QString rel  = "wallpapers/" + pathOrUrl.mid(wpPrefix.size());
            const QString file = toFileUrlIfExists(QDir(dataDir).filePath(rel));
            return file.isEmpty() ? pathOrUrl : file;
        }

        const QString sndPrefix = "qrc:/sounds/resources/sounds/";
        if (pathOrUrl.startsWith(sndPrefix)) {
            const QString rel  = "sounds/" + pathOrUrl.mid(sndPrefix.size());
            const QString file = toFileUrlIfExists(QDir(dataDir).filePath(rel));
            return file.isEmpty() ? pathOrUrl : file;
        }

        return pathOrUrl;
    }

    QStringList scanSoundDir(const QString &dataDir, const QString &subdir) {
        QStringList out;
        if (dataDir.isEmpty())
            return out;
        const QString base = QDir(dataDir).filePath("sounds/" + subdir);
        if (!QDir(base).exists())
            return out;
        const QStringList filters = {"*.wav", "*.ogg", "*.mp3", "*.m4a"};
        QDirIterator      it(base, filters, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString abs = it.next();
            out.push_back(QUrl::fromLocalFile(abs).toString());
        }
        out.sort(Qt::CaseInsensitive);
        return out;
    }
}

QString SettingsManager::assetUrl(const QString &relativePath) const {
    const QString dir = dataDirFromEnvOrDefault();
    if (!dir.isEmpty()) {
        const QString abs  = QDir(dir).filePath(relativePath);
        const QString file = toFileUrlIfExists(abs);
        if (!file.isEmpty())
            return file;
    }
    const QString qrc = qrcFallbackForRelative(relativePath);
    return qrc.isEmpty() ? relativePath : qrc;
}

void SettingsManager::load() {
    const QString dataDir = dataDirFromEnvOrDefault();

    m_userScaleFactor = m_settings.value("ui/userScaleFactor", 1.0).toReal();
    m_wallpaperPath =
        m_settings.value("ui/wallpaperPath", assetUrl("wallpapers/meridian.jpg")).toString();
    m_wallpaperPath = migrateQrcToFile(m_wallpaperPath, dataDir);

    m_deviceName               = m_settings.value("system/deviceName", "Marathon OS").toString();
    m_autoLock                 = m_settings.value("system/autoLock", true).toBool();
    m_autoLockTimeout          = m_settings.value("system/autoLockTimeout", 0).toInt();
    // Before the lock delay, autoLockTimeout was unused (stored as 300) and
    // autoLock off meant "don't lock on idle": give those users the longest delay.
    if (!m_settings.value("system/autoLockTimeoutMigrated", false).toBool()) {
        m_autoLockTimeout = m_autoLock ? 0 : 300;
        m_settings.setValue("system/autoLockTimeout", m_autoLockTimeout);
        m_settings.setValue("system/autoLockTimeoutMigrated", true);
    }
    m_showNotificationPreviews = m_settings.value("system/showNotificationPreviews", true).toBool();
    m_timeFormat               = m_settings.value("system/timeFormat", "12h").toString();
    m_dateFormat               = m_settings.value("system/dateFormat", "US").toString();

    m_ringtone = m_settings.value("audio/ringtone", assetUrl("sounds/phone/bbpro1.wav")).toString();
    m_ringtone = migrateQrcToFile(m_ringtone, dataDir);
    m_notificationSound =
        m_settings.value("audio/notificationSound", assetUrl("sounds/text/chime.wav")).toString();
    m_notificationSound = migrateQrcToFile(m_notificationSound, dataDir);
    m_alarmSound = m_settings.value("audio/alarmSound", assetUrl("sounds/alarms/alarm_sunrise.wav"))
                       .toString();
    m_alarmSound         = migrateQrcToFile(m_alarmSound, dataDir);
    m_mediaVolume        = m_settings.value("audio/mediaVolume", 0.6).toReal();
    m_ringtoneVolume     = m_settings.value("audio/ringtoneVolume", 0.8).toReal();
    m_alarmVolume        = m_settings.value("audio/alarmVolume", 0.9).toReal();
    m_notificationVolume = m_settings.value("audio/notificationVolume", 0.7).toReal();
    m_systemVolume       = m_settings.value("audio/systemVolume", 0.5).toReal();
    m_dndEnabled         = m_settings.value("audio/dndEnabled", false).toBool();
    m_vibrationEnabled   = m_settings.value("audio/vibrationEnabled", true).toBool();
    m_reduceMotion       = m_settings.value("accessibility/reduceMotion", false).toBool();
    m_automaticTimeZone  = m_settings.value("time/automaticTimeZone", true).toBool();
    m_audioProfile       = m_settings.value("audio/audioProfile", "normal").toString();

    m_screenTimeout = m_settings.value("display/screenTimeout", DeviceProfile::instance().screenTimeoutMs()).toInt();
    // Default ON — adaptive brightness should "just work" out of the box
    // (it never drops below the visible floor). Users can disable it.
    m_autoBrightness = m_settings.value("display/autoBrightness", true).toBool();
    m_statusBarClockPosition =
        m_settings.value("display/statusBarClockPosition", "center").toString();

    m_showNotificationsOnLockScreen =
        m_settings.value("notifications/showOnLockScreen", true).toBool();

    m_filterMobileFriendlyApps = m_settings.value("apps/filterMobileFriendly", true).toBool();
    // Terminal default-hidden so a consumer phone doesn't ship a shell
    // prompt as a first-class launcher entry. Still reachable via
    // Settings → Apps → Hidden Apps.
    m_hiddenApps =
        m_settings.value("apps/hiddenApps", QStringList{"terminal", "test"}).toStringList();
    // Once only, so a developer who unhides the Test Suite keeps it.
    if (!m_settings.value("apps/testHiddenByDefault", false).toBool()) {
        if (!m_hiddenApps.contains(QStringLiteral("test")))
            m_hiddenApps.append(QStringLiteral("test"));
        m_settings.setValue("apps/hiddenApps", m_hiddenApps);
        m_settings.setValue("apps/testHiddenByDefault", true);
    }
    m_appSortOrder   = m_settings.value("apps/sortOrder", "alphabetical").toString();
    m_appGridColumns = m_settings.value("apps/gridColumns", 0).toInt();
    m_searchNativeApps       = m_settings.value("apps/searchNativeApps", true).toBool();
    m_showNotificationBadges = m_settings.value("apps/showBadges", true).toBool();
    m_appNotificationSettings =
        m_settings.value("notifications/appSettings", QVariantMap()).toMap();
    m_showFrequentApps = m_settings.value("apps/showFrequentApps", false).toBool();

    // Seed defaultXxx from the marathon-shipped app IDs so the role
    // resolver (used by web-link openers, mailto: handlers, dialer
    // intents) has something to resolve to on a clean install. Without
    // these seeds every "open in default…" path is broken until the
    // user manually picks an app in Settings — which doesn't happen
    // because there's no UI surface that prompts. Marathon app IDs:
    //   browser, camera, email, gallery,
    //   messages, music, phone (defaultFor "dialer").
    // video/files are intentionally empty — Marathon doesn't ship a
    // first-party video player or file manager today; let the resolver
    // fall back to the user's manual pick.
    //
    // QSettings::value's fallback fires only when the key is ABSENT. A
    // previous shell launch may have committed empty strings (rXXX
    // wrote them eagerly) — for that case we treat empty-string as
    // "unseeded" and substitute the marathon ID; persistence happens
    // on the next save().
    const auto pickDefault = [this](const char *key, const QString &fallback) -> QString {
        const QString v = m_settings.value(key, fallback).toString();
        return v.isEmpty() ? fallback : v;
    };
    QVariantMap defaultApps;
    // Pacific is Marathon's browser where it's installed.
    const QString browser = QFile::exists(QStringLiteral("/usr/share/applications/shipwright-pacific.desktop"))
                                ? QStringLiteral("shipwright-pacific")
                                : QStringLiteral("browser");
    defaultApps["browser"]   = pickDefault("apps/defaultBrowser", browser);
    defaultApps["dialer"]    = pickDefault("apps/defaultDialer", QStringLiteral("phone"));
    defaultApps["messaging"] = pickDefault("apps/defaultMessaging", QStringLiteral("messages"));
    defaultApps["email"]     = pickDefault("apps/defaultEmail", QStringLiteral("email"));
    defaultApps["camera"]    = pickDefault("apps/defaultCamera", QStringLiteral("camera"));
    defaultApps["gallery"]   = pickDefault("apps/defaultGallery", QStringLiteral("gallery"));
    defaultApps["music"]     = pickDefault("apps/defaultMusic", QStringLiteral("music"));
    defaultApps["video"]     = m_settings.value("apps/defaultVideo", "").toString();
    defaultApps["files"]     = m_settings.value("apps/defaultFiles", "").toString();
    m_defaultApps            = defaultApps;

    m_firstRunComplete = m_settings.value("system/firstRunComplete", false).toBool();

    // MarathonQuickSettings.qml tile IDs; the old "enabledTiles" key used other IDs.
    QStringList defaultTiles = {"wifi",           "cellular", "bluetooth", "airplane",   "dnd",
                                "torch",          "location", "hotspot",   "nightlight", "rotation",
                                "autobrightness", "lowpower", "vibration", "power"};
    m_enabledQuickSettingsTiles =
        m_settings.value("quicksettings/tiles", defaultTiles).toStringList();
    m_quickSettingsTileOrder =
        m_settings.value("quicksettings/tileOrder", defaultTiles).toStringList();

    m_keyboardAutoCorrection = m_settings.value("keyboard/autoCorrection", true).toBool();
    m_keyboardAutoCapitalize = m_settings.value("keyboard/autoCapitalize", true).toBool();
    m_keyboardPredictiveText = m_settings.value("keyboard/predictiveText", true).toBool();
    m_keyboardHapticStrength = m_settings.value("keyboard/hapticStrength", "medium").toString();
    m_keyboardLanguage       = m_settings.value("keyboard/language", "en_US").toString();

    m_unifiedPushFallbackEnabled =
        m_settings.value("notifications/unifiedPushFallback", false).toBool();

    qDebug() << "[SettingsManager] Loaded: userScaleFactor =" << m_userScaleFactor;
    qDebug() << "[SettingsManager] Loaded: wallpaperPath =" << m_wallpaperPath;
    qDebug() << "[SettingsManager] Loaded: firstRunComplete =" << m_firstRunComplete;
    qDebug() << "[SettingsManager] Loaded: filterMobileFriendlyApps ="
             << m_filterMobileFriendlyApps;
    qDebug() << "[SettingsManager] Loaded: hiddenApps =" << m_hiddenApps;
    qDebug() << "[SettingsManager] Loaded: appSortOrder =" << m_appSortOrder;
}

void SettingsManager::flush() {
    // Mark this write as self-originated so the QFileSystemWatcher callback
    // doesn't echo the value back through load() and re-emit *Changed signals
    // we already emitted from the setter. Re-armed after a short delay so
    // the watcher's notification, which fires after sync(), is filtered.
    m_inSelfWrite = true;
    m_settings.sync();
    QTimer::singleShot(200, this, [this]() { m_inSelfWrite = false; });
}

// The file is rewritten (and fsynced) once a burst of changes settles: a
// volume or brightness drag calls this per step on the GUI thread.
void SettingsManager::save() {
    m_settings.setValue("ui/userScaleFactor", m_userScaleFactor);
    m_settings.setValue("ui/wallpaperPath", m_wallpaperPath);

    m_settings.setValue("system/deviceName", m_deviceName);
    m_settings.setValue("system/autoLock", m_autoLock);
    m_settings.setValue("system/autoLockTimeout", m_autoLockTimeout);
    m_settings.setValue("system/showNotificationPreviews", m_showNotificationPreviews);
    m_settings.setValue("system/timeFormat", m_timeFormat);
    m_settings.setValue("system/dateFormat", m_dateFormat);

    m_settings.setValue("audio/ringtone", m_ringtone);
    m_settings.setValue("audio/notificationSound", m_notificationSound);
    m_settings.setValue("audio/alarmSound", m_alarmSound);
    m_settings.setValue("audio/mediaVolume", m_mediaVolume);
    m_settings.setValue("audio/ringtoneVolume", m_ringtoneVolume);
    m_settings.setValue("audio/alarmVolume", m_alarmVolume);
    m_settings.setValue("audio/notificationVolume", m_notificationVolume);
    m_settings.setValue("audio/systemVolume", m_systemVolume);
    m_settings.setValue("audio/dndEnabled", m_dndEnabled);
    m_settings.setValue("audio/vibrationEnabled", m_vibrationEnabled);
    m_settings.setValue("accessibility/reduceMotion", m_reduceMotion);
    m_settings.setValue("time/automaticTimeZone", m_automaticTimeZone);
    m_settings.setValue("audio/audioProfile", m_audioProfile);

    m_settings.setValue("display/screenTimeout", m_screenTimeout);
    m_settings.setValue("display/autoBrightness", m_autoBrightness);
    m_settings.setValue("display/statusBarClockPosition", m_statusBarClockPosition);

    m_settings.setValue("notifications/showOnLockScreen", m_showNotificationsOnLockScreen);
    m_settings.setValue("notifications/appSettings", m_appNotificationSettings);

    m_settings.setValue("apps/filterMobileFriendly", m_filterMobileFriendlyApps);
    m_settings.setValue("apps/hiddenApps", m_hiddenApps);
    m_settings.setValue("apps/sortOrder", m_appSortOrder);
    m_settings.setValue("apps/gridColumns", m_appGridColumns);
    m_settings.setValue("apps/searchNativeApps", m_searchNativeApps);
    m_settings.setValue("apps/showBadges", m_showNotificationBadges);
    m_settings.setValue("apps/showFrequentApps", m_showFrequentApps);

    m_settings.setValue("apps/defaultBrowser", m_defaultApps.value("browser", "").toString());
    m_settings.setValue("apps/defaultDialer", m_defaultApps.value("dialer", "").toString());
    m_settings.setValue("apps/defaultMessaging", m_defaultApps.value("messaging", "").toString());
    m_settings.setValue("apps/defaultEmail", m_defaultApps.value("email", "").toString());
    m_settings.setValue("apps/defaultCamera", m_defaultApps.value("camera", "").toString());
    m_settings.setValue("apps/defaultGallery", m_defaultApps.value("gallery", "").toString());
    m_settings.setValue("apps/defaultMusic", m_defaultApps.value("music", "").toString());
    m_settings.setValue("apps/defaultVideo", m_defaultApps.value("video", "").toString());
    m_settings.setValue("apps/defaultFiles", m_defaultApps.value("files", "").toString());

    m_settings.setValue("system/firstRunComplete", m_firstRunComplete);

    m_settings.setValue("quicksettings/tiles", m_enabledQuickSettingsTiles);
    m_settings.setValue("quicksettings/tileOrder", m_quickSettingsTileOrder);

    m_settings.setValue("keyboard/autoCorrection", m_keyboardAutoCorrection);
    m_settings.setValue("keyboard/autoCapitalize", m_keyboardAutoCapitalize);
    m_settings.setValue("keyboard/predictiveText", m_keyboardPredictiveText);
    m_settings.setValue("keyboard/hapticStrength", m_keyboardHapticStrength);
    m_settings.setValue("keyboard/language", m_keyboardLanguage);

    m_settings.setValue("notifications/unifiedPushFallback", m_unifiedPushFallbackEnabled);

    m_flushTimer.start();
}

void SettingsManager::setUnifiedPushFallbackEnabled(bool enabled) {
    if (m_unifiedPushFallbackEnabled == enabled)
        return;
    m_unifiedPushFallbackEnabled = enabled;
    save();
    emit unifiedPushFallbackEnabledChanged();
}

void SettingsManager::setUserScaleFactor(qreal factor) {
    // Clamp to the union of every scale the OOBE + Settings ScalePage
    // expose (0.75 .. 1.5). A corrupt or out-of-band value reaching
    // save() would persist nonsense to the user's conf and the next
    // load() would feed it back into every layout binding — better to
    // reject at the door and log the offender than to plaster it across
    // disk and chase the symptom later.
    const qreal clamped = qBound<qreal>(0.5, factor, 2.0);
    if (!qFuzzyCompare(clamped, factor)) {
        qWarning() << "[SettingsManager] userScaleFactor" << factor << "out of range, clamped to"
                   << clamped;
    }
    if (qFuzzyCompare(m_userScaleFactor, clamped)) {
        return;
    }

    m_userScaleFactor = clamped;
    save();
    emit userScaleFactorChanged();

    qInfo() << "[SettingsManager] userScaleFactor persisted at" << clamped;
}

void SettingsManager::setWallpaperPath(const QString &path) {
    if (m_wallpaperPath == path) {
        return;
    }

    m_wallpaperPath = path;
    save();
    emit wallpaperPathChanged();

    qDebug() << "[SettingsManager] wallpaperPath changed to" << path;
}

void SettingsManager::setDeviceName(const QString &name) {
    if (m_deviceName == name)
        return;
    m_deviceName = name;
    save();
    emit deviceNameChanged();
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.hostname1"), QStringLiteral("/org/freedesktop/hostname1"),
        QStringLiteral("org.freedesktop.hostname1"), QStringLiteral("SetPrettyHostname"));
    msg << name << false;
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<> reply = *w;
        if (reply.isError())
            qWarning() << "[SettingsManager] SetPrettyHostname failed:" << reply.error().message();
    });
}

void SettingsManager::setAutoLock(bool enabled) {
    if (m_autoLock == enabled)
        return;
    m_autoLock = enabled;
    save();
    emit autoLockChanged();
}

void SettingsManager::setAutoLockTimeout(int seconds) {
    if (m_autoLockTimeout == seconds)
        return;
    m_autoLockTimeout = seconds;
    save();
    emit autoLockTimeoutChanged();
}

void SettingsManager::setShowNotificationPreviews(bool show) {
    if (m_showNotificationPreviews == show)
        return;
    m_showNotificationPreviews = show;
    save();
    emit showNotificationPreviewsChanged();
}

void SettingsManager::setTimeFormat(const QString &format) {
    if (m_timeFormat == format)
        return;
    m_timeFormat = format;
    save();
    emit timeFormatChanged();
}

void SettingsManager::setDateFormat(const QString &format) {
    if (m_dateFormat == format)
        return;
    m_dateFormat = format;
    save();
    emit dateFormatChanged();
}

void SettingsManager::setRingtone(const QString &path) {
    if (m_ringtone == path)
        return;
    m_ringtone = path;
    save();
    emit ringtoneChanged();
    qDebug() << "[SettingsManager] Ringtone changed to" << path;
}

void SettingsManager::setNotificationSound(const QString &path) {
    if (m_notificationSound == path)
        return;
    m_notificationSound = path;
    save();
    emit notificationSoundChanged();
    qDebug() << "[SettingsManager] Notification sound changed to" << path;
}

void SettingsManager::setAlarmSound(const QString &path) {
    if (m_alarmSound == path)
        return;
    m_alarmSound = path;
    save();
    emit alarmSoundChanged();
    qDebug() << "[SettingsManager] Alarm sound changed to" << path;
}

void SettingsManager::setMediaVolume(qreal volume) {
    if (qFuzzyCompare(m_mediaVolume, volume))
        return;
    m_mediaVolume = qBound(0.0, volume, 1.0);
    save();
    emit mediaVolumeChanged();
    qDebug() << "[SettingsManager] Media volume changed to" << m_mediaVolume;
}

void SettingsManager::setRingtoneVolume(qreal volume) {
    if (qFuzzyCompare(m_ringtoneVolume, volume))
        return;
    m_ringtoneVolume = qBound(0.0, volume, 1.0);
    save();
    emit ringtoneVolumeChanged();
    qDebug() << "[SettingsManager] Ringtone volume changed to" << m_ringtoneVolume;
}

void SettingsManager::setAlarmVolume(qreal volume) {
    if (qFuzzyCompare(m_alarmVolume, volume))
        return;
    m_alarmVolume = qBound(0.0, volume, 1.0);
    save();
    emit alarmVolumeChanged();
    qDebug() << "[SettingsManager] Alarm volume changed to" << m_alarmVolume;
}

void SettingsManager::setNotificationVolume(qreal volume) {
    if (qFuzzyCompare(m_notificationVolume, volume))
        return;
    m_notificationVolume = qBound(0.0, volume, 1.0);
    save();
    emit notificationVolumeChanged();
    qDebug() << "[SettingsManager] Notification volume changed to" << m_notificationVolume;
}

void SettingsManager::setSystemVolume(qreal volume) {
    if (qFuzzyCompare(m_systemVolume, volume))
        return;
    m_systemVolume = qBound(0.0, volume, 1.0);
    save();
    emit systemVolumeChanged();
    qDebug() << "[SettingsManager] System volume changed to" << m_systemVolume;
}

void SettingsManager::setDndEnabled(bool enabled) {
    if (m_dndEnabled == enabled)
        return;
    m_dndEnabled = enabled;
    save();
    emit dndEnabledChanged();
    qDebug() << "[SettingsManager] DND enabled changed to" << m_dndEnabled;
}

void SettingsManager::setReduceMotion(bool enabled) {
    if (m_reduceMotion == enabled)
        return;
    m_reduceMotion = enabled;
    save();
    emit reduceMotionChanged();
}

QString SettingsManager::timeZone() const {
    const QString target = QFileInfo(QStringLiteral("/etc/localtime")).symLinkTarget();
    const int     idx    = target.indexOf(QLatin1String("zoneinfo/"));
    if (idx >= 0)
        return target.mid(idx + 9);
    return QString::fromUtf8(QTimeZone::systemTimeZoneId());
}

static QDBusMessage timedateCall(const QString &method) {
    return QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.timedate1"), QStringLiteral("/org/freedesktop/timedate1"),
        QStringLiteral("org.freedesktop.timedate1"), method);
}

void SettingsManager::watchTimedate() {
    QDBusConnection bus = QDBusConnection::systemBus();
    bus.connect(QStringLiteral("org.freedesktop.timedate1"),
                QStringLiteral("/org/freedesktop/timedate1"),
                QStringLiteral("org.freedesktop.DBus.Properties"),
                QStringLiteral("PropertiesChanged"), this,
                SLOT(onTimedatePropertiesChanged(QString, QVariantMap, QStringList)));
    QDBusMessage get = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.timedate1"), QStringLiteral("/org/freedesktop/timedate1"),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    get << QStringLiteral("org.freedesktop.timedate1") << QStringLiteral("NTP");
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(get), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusVariant> reply = *w;
        if (!reply.isError())
            onTimedatePropertiesChanged({}, {{QStringLiteral("NTP"), reply.value().variant()}}, {});
    });
}

void SettingsManager::onTimedatePropertiesChanged(const QString &, const QVariantMap &changed,
                                                  const QStringList &) {
    const auto ntp = changed.constFind(QStringLiteral("NTP"));
    if (ntp != changed.constEnd() && ntp->toBool() != m_automaticTime) {
        m_automaticTime = ntp->toBool();
        emit automaticTimeChanged();
    }
    if (changed.contains(QStringLiteral("Timezone")))
        emit timeZoneChanged();
}

void SettingsManager::setAutomaticTime(bool enabled) {
    QDBusMessage msg = timedateCall(QStringLiteral("SetNTP"));
    msg << enabled << false;
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, enabled](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                QDBusPendingReply<> reply = *w;
                if (reply.isError()) {
                    qWarning() << "[SettingsManager] SetNTP failed:" << reply.error().message();
                    emit automaticTimeChanged();
                    emit dateTimeChangeFailed(reply.error().message());
                    return;
                }
                if (m_automaticTime != enabled) {
                    m_automaticTime = enabled;
                    emit automaticTimeChanged();
                }
            });
}

void SettingsManager::setAutomaticTimeZone(bool enabled) {
    if (m_automaticTimeZone == enabled)
        return;
    m_automaticTimeZone = enabled;
    save();
    emit automaticTimeZoneChanged();
}

void SettingsManager::setSystemTime(qint64 msecsSinceEpoch) {
    QDBusMessage msg = timedateCall(QStringLiteral("SetTime"));
    msg << msecsSinceEpoch * 1000 << false << false;
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<> reply = *w;
        if (reply.isError()) {
            qWarning() << "[SettingsManager] SetTime failed:" << reply.error().message();
            emit dateTimeChangeFailed(reply.error().message());
        }
    });
}

void SettingsManager::setTimeZone(const QString &zoneId) {
    if (zoneId.isEmpty() || zoneId == timeZone() || !QTimeZone(zoneId.toUtf8()).isValid())
        return;
    QDBusMessage msg = timedateCall(QStringLiteral("SetTimezone"));
    msg << zoneId << false;
    auto *watcher =
        new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, zoneId](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                QDBusPendingReply<> reply = *w;
                if (reply.isError()) {
                    qWarning() << "[SettingsManager] SetTimezone" << zoneId
                               << "failed:" << reply.error().message();
                    emit timeZoneChanged();
                    emit dateTimeChangeFailed(reply.error().message());
                    return;
                }
                // musl caches the zone until TZ changes; children inherit it too.
                qputenv("TZ", (QStringLiteral(":") + zoneId).toUtf8());
                tzset();
                emit timeZoneChanged();
            });
}

void SettingsManager::setVibrationEnabled(bool enabled) {
    if (m_vibrationEnabled == enabled)
        return;
    m_vibrationEnabled = enabled;
    save();
    emit vibrationEnabledChanged();
    qDebug() << "[SettingsManager] Vibration enabled changed to" << m_vibrationEnabled;
}

void SettingsManager::setAudioProfile(const QString &profile) {
    if (m_audioProfile == profile)
        return;
    m_audioProfile = profile;
    save();
    emit audioProfileChanged();
    qDebug() << "[SettingsManager] Audio profile changed to" << m_audioProfile;
}

void SettingsManager::setScreenTimeout(int ms) {
    // Canonical idle timeout: the shell's idle timers read this. DisplayManagerCpp::screenTimeout
    // (s) is a mirror DisplayPolicyController copies it into; nothing blanks from the mirror.
    if (m_screenTimeout == ms)
        return;
    m_screenTimeout = ms;
    save();
    emit screenTimeoutChanged();
    qDebug() << "[SettingsManager] Screen timeout changed to" << ms;
}

void SettingsManager::setAutoBrightness(bool enabled) {
    if (m_autoBrightness == enabled)
        return;
    m_autoBrightness = enabled;
    save();
    emit autoBrightnessChanged();
    qDebug() << "[SettingsManager] Auto-brightness changed to" << enabled;
}

void SettingsManager::setStatusBarClockPosition(const QString &position) {
    if (m_statusBarClockPosition == position)
        return;

    if (position != "left" && position != "center" && position != "right") {
        qWarning() << "[SettingsManager] Invalid clock position:" << position << "- using 'center'";
        return;
    }
    m_statusBarClockPosition = position;
    save();
    emit statusBarClockPositionChanged();
    qDebug() << "[SettingsManager] Status bar clock position changed to" << position;
}

void SettingsManager::setShowNotificationsOnLockScreen(bool enabled) {
    if (m_showNotificationsOnLockScreen == enabled)
        return;
    m_showNotificationsOnLockScreen = enabled;
    save();
    emit showNotificationsOnLockScreenChanged();
}

void SettingsManager::setFirstRunComplete(bool complete) {
    if (m_firstRunComplete == complete)
        return;
    m_firstRunComplete = complete;
    save();
    emit firstRunCompleteChanged();
    qDebug() << "[SettingsManager] First run complete changed to" << complete;
}

void SettingsManager::setEnabledQuickSettingsTiles(const QStringList &tiles) {
    if (m_enabledQuickSettingsTiles == tiles)
        return;
    m_enabledQuickSettingsTiles = tiles;
    save();
    emit enabledQuickSettingsTilesChanged();
    qDebug() << "[SettingsManager] Enabled Quick Settings tiles changed:" << tiles;
}

void SettingsManager::setQuickSettingsTileOrder(const QStringList &order) {
    if (m_quickSettingsTileOrder == order)
        return;
    m_quickSettingsTileOrder = order;
    save();
    emit quickSettingsTileOrderChanged();
    qDebug() << "[SettingsManager] Quick Settings tile order changed:" << order;
}

void SettingsManager::setKeyboardAutoCorrection(bool enabled) {
    if (m_keyboardAutoCorrection == enabled)
        return;
    m_keyboardAutoCorrection = enabled;
    save();
    emit keyboardAutoCorrectionChanged();
    qDebug() << "[SettingsManager] Keyboard auto-correction:" << enabled;
}

void SettingsManager::setKeyboardAutoCapitalize(bool enabled) {
    if (m_keyboardAutoCapitalize == enabled)
        return;
    m_keyboardAutoCapitalize = enabled;
    save();
    emit keyboardAutoCapitalizeChanged();
    qDebug() << "[SettingsManager] Keyboard auto-capitalize:" << enabled;
}

void SettingsManager::setKeyboardPredictiveText(bool enabled) {
    if (m_keyboardPredictiveText == enabled)
        return;
    m_keyboardPredictiveText = enabled;
    save();
    emit keyboardPredictiveTextChanged();
    qDebug() << "[SettingsManager] Keyboard predictive text:" << enabled;
}

void SettingsManager::setKeyboardHapticStrength(const QString &strength) {
    if (m_keyboardHapticStrength == strength)
        return;
    m_keyboardHapticStrength = strength;
    save();
    emit keyboardHapticStrengthChanged();
}

void SettingsManager::setKeyboardLanguage(const QString &language) {
    if (m_keyboardLanguage == language)
        return;
    m_keyboardLanguage = language;
    save();
    emit keyboardLanguageChanged();
}

QStringList SettingsManager::availableRingtones() {
    const QString dataDir = dataDirFromEnvOrDefault();
    QStringList   ringtones;
    ringtones += scanSoundDir(dataDir, "phone");
    ringtones += scanSoundDir(dataDir, "bbm");

    if (!ringtones.isEmpty()) {
        qDebug() << "[SettingsManager] Available ringtones (filesystem):" << ringtones.size();
        return ringtones;
    }

    ringtones = {"qrc:/sounds/resources/sounds/phone/bbpro1.wav",
                 "qrc:/sounds/resources/sounds/phone/bbpro2.wav",
                 "qrc:/sounds/resources/sounds/phone/bbpro3.wav",
                 "qrc:/sounds/resources/sounds/phone/bbpro4.wav",
                 "qrc:/sounds/resources/sounds/bbm/bbpro5.wav",
                 "qrc:/sounds/resources/sounds/bbm/bbpro6.wav",
                 "qrc:/sounds/resources/sounds/phone/bonjour.wav",
                 "qrc:/sounds/resources/sounds/phone/classicphone.wav",
                 "qrc:/sounds/resources/sounds/phone/clean.wav",
                 "qrc:/sounds/resources/sounds/phone/evolving_destiny.wav",
                 "qrc:/sounds/resources/sounds/phone/fresh.wav",
                 "qrc:/sounds/resources/sounds/phone/lively.wav",
                 "qrc:/sounds/resources/sounds/phone/open.wav",
                 "qrc:/sounds/resources/sounds/phone/radiant.wav",
                 "qrc:/sounds/resources/sounds/phone/spirit.wav"};

    qDebug() << "[SettingsManager] Available ringtones:" << ringtones.size();
    return ringtones;
}

QStringList SettingsManager::availableNotificationSounds() {
    const QString dataDir = dataDirFromEnvOrDefault();
    QStringList   sounds;
    sounds += scanSoundDir(dataDir, "text");
    sounds += scanSoundDir(dataDir, "messages");
    sounds += scanSoundDir(dataDir, "bbm");

    if (!sounds.isEmpty()) {
        qDebug() << "[SettingsManager] Available notification sounds (filesystem):"
                 << sounds.size();
        return sounds;
    }

    sounds = {"qrc:/sounds/resources/sounds/text/bikebell.wav",
              "qrc:/sounds/resources/sounds/text/brief.wav",
              "qrc:/sounds/resources/sounds/text/caffeine.wav",
              "qrc:/sounds/resources/sounds/text/chigong.wav",
              "qrc:/sounds/resources/sounds/text/chime.wav",
              "qrc:/sounds/resources/sounds/text/crystal.wav",
              "qrc:/sounds/resources/sounds/text/lucid.wav",
              "qrc:/sounds/resources/sounds/text/presto.wav",
              "qrc:/sounds/resources/sounds/text/pure.wav",
              "qrc:/sounds/resources/sounds/text/tight.wav",
              "qrc:/sounds/resources/sounds/text/ufo.wav",

              "qrc:/sounds/resources/sounds/messages/bright.wav",
              "qrc:/sounds/resources/sounds/messages/confident.wav",
              "qrc:/sounds/resources/sounds/messages/contentment.wav",
              "qrc:/sounds/resources/sounds/messages/eager.wav",
              "qrc:/sounds/resources/sounds/messages/gungho.wav"};

    qDebug() << "[SettingsManager] Available notification sounds:" << sounds.size();
    return sounds;
}

QStringList SettingsManager::availableAlarmSounds() {
    const QString dataDir = dataDirFromEnvOrDefault();
    QStringList   alarms  = scanSoundDir(dataDir, "alarms");

    if (!alarms.isEmpty()) {
        qDebug() << "[SettingsManager] Available alarm sounds (filesystem):" << alarms.size();
        return alarms;
    }

    alarms = {"qrc:/sounds/resources/sounds/alarms/alarm_antelope.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_bbproalarm.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_definite.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_earlyriser.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_electronic.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_highalert.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_sunrise.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_transition.wav",
              "qrc:/sounds/resources/sounds/alarms/alarm_vintagealarm.wav"};

    qDebug() << "[SettingsManager] Available alarm sounds:" << alarms.size();
    return alarms;
}

QStringList SettingsManager::screenTimeoutOptions() {
    return QStringList() << "30 seconds" << "1 minute" << "2 minutes" << "5 minutes" << "Never";
}

int SettingsManager::screenTimeoutValue(const QString &option) {
    if (option == "30 seconds")
        return 30000;
    if (option == "1 minute")
        return 60000;
    if (option == "2 minutes")
        return 120000;
    if (option == "5 minutes")
        return 300000;
    if (option == "Never")
        return 0;
    return 120000;
}

void SettingsManager::setFilterMobileFriendlyApps(bool enabled) {
    if (m_filterMobileFriendlyApps == enabled) {
        return;
    }

    m_filterMobileFriendlyApps = enabled;
    emit filterMobileFriendlyAppsChanged();
    save();

    qDebug() << "[SettingsManager] Filter mobile-friendly apps:" << enabled;
}

void SettingsManager::setHiddenApps(const QStringList &apps) {
    if (m_hiddenApps == apps) {
        return;
    }

    m_hiddenApps = apps;
    emit hiddenAppsChanged();
    save();

    qDebug() << "[SettingsManager] Hidden apps:" << apps.size();
}

void SettingsManager::setAppSortOrder(const QString &order) {
    if (m_appSortOrder == order) {
        return;
    }

    m_appSortOrder = order;
    emit appSortOrderChanged();
    save();

    qDebug() << "[SettingsManager] App sort order:" << order;
}

void SettingsManager::setAppGridColumns(int columns) {
    if (m_appGridColumns == columns) {
        return;
    }

    m_appGridColumns = columns;
    emit appGridColumnsChanged();
    save();

    qDebug() << "[SettingsManager] App grid columns:" << columns;
}

void SettingsManager::setSearchNativeApps(bool enabled) {
    if (m_searchNativeApps == enabled) {
        return;
    }

    m_searchNativeApps = enabled;
    emit searchNativeAppsChanged();
    save();

    qDebug() << "[SettingsManager] Search native apps:" << enabled;
}

void SettingsManager::setShowNotificationBadges(bool enabled) {
    if (m_showNotificationBadges == enabled) {
        return;
    }

    m_showNotificationBadges = enabled;
    emit showNotificationBadgesChanged();
    save();

    qDebug() << "[SettingsManager] Show notification badges:" << enabled;
}

void SettingsManager::setAppNotificationSettings(const QVariantMap &settings) {
    if (m_appNotificationSettings == settings) {
        return;
    }
    m_appNotificationSettings = settings;
    emit appNotificationSettingsChanged();
    save();
}

bool SettingsManager::isNotificationsEnabledForApp(const QString &appId) const {
    if (appId.isEmpty()) {
        return true;
    }
    const QVariant value = m_appNotificationSettings.value(appId);
    if (!value.isValid()) {
        return true;
    }
    return value.toBool();
}

void SettingsManager::setShowFrequentApps(bool enabled) {
    if (m_showFrequentApps == enabled) {
        return;
    }

    m_showFrequentApps = enabled;
    emit showFrequentAppsChanged();
    save();

    qDebug() << "[SettingsManager] Show frequent apps:" << enabled;
}

void SettingsManager::setDefaultApps(const QVariantMap &apps) {
    if (m_defaultApps == apps) {
        return;
    }

    m_defaultApps = apps;
    emit defaultAppsChanged();
    save();

    qDebug() << "[SettingsManager] Default apps updated";
}

QString SettingsManager::formatSoundName(const QString &path) {
    return ::formatSoundName(path);
}

// A value QSettings can't stream (a QDBusArgument) breaks every later save.
static bool storable(const QVariant &v) {
    if (v.typeId() == QMetaType::QVariantList) {
        const QVariantList l = v.toList();
        return std::all_of(l.cbegin(), l.cend(), storable);
    }
    if (v.typeId() == QMetaType::QVariantMap) {
        const QVariantMap m = v.toMap();
        return std::all_of(m.cbegin(), m.cend(), storable);
    }
    return !v.isValid() || v.metaType().hasRegisteredDataStreamOperators();
}

QVariant SettingsManager::get(const QString &key, const QVariant &defaultValue) {
    QVariant v = m_settings.value(key, defaultValue);
    if (storable(v))
        return v;
    m_settings.remove(key);
    return defaultValue;
}

void SettingsManager::set(const QString &key, const QVariant &value) {
    if (!storable(value)) {
        qWarning() << "[SettingsManager] not storing" << key << "of type" << value.metaType().name();
        return;
    }
    m_settings.setValue(key, value);
}

void SettingsManager::sync() {
    m_settings.sync();
}

void SettingsManager::removeAppKeys(const QString &appId) {
    // QSettings::remove("") would clear every setting.
    if (appId.isEmpty())
        return;
    m_settings.remove(appId);
}
