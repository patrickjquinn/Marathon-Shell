#include "systemcontrolstore.h"
#include "src/controllers/audiopolicycontroller.h"
#include "marathon-shell-native/src/alarms.cxxqt.h"
#include "marathon-shell-native/src/audio.cxxqt.h"
#include "marathon-shell-native/src/bluetooth.cxxqt.h"
#include "marathon-shell-native/src/display.cxxqt.h"
#include "marathon-shell-native/src/flashlight.cxxqt.h"
#include "marathon-shell-native/src/haptics.cxxqt.h"
#include "marathon-shell-native/src/location.cxxqt.h"
#include "marathon-shell-native/src/modem.cxxqt.h"
#include "marathon-shell-native/src/network.cxxqt.h"
#include "marathon-shell-native/src/power.cxxqt.h"
#include "marathon-shell-native/src/settings.cxxqt.h"
#include "src/services/screenshotservicecpp.h"
#include <QRandomGenerator>
#include <QTimer>
#include <cmath>
#include <algorithm>

SystemControlStore::SystemControlStore(
    Network *networkManager, Bluetooth *bluetoothManager,
    marathon::Display *display, Flashlight *flashlightManager,
    Modem *modemManager, marathon::Settings *settingsManager, Alarms *alarmManager,
    Location *locationManager, Haptics *hapticManager, Power *powerManager,
    marathon::Audio *audioManager, AudioPolicyController *audioPolicyController,
    ScreenshotServiceCpp *screenshotService, QObject *parent)
    : QObject(parent)
    , m_networkManager(networkManager)
    , m_bluetoothManager(bluetoothManager)
    , m_display(display)
    , m_flashlightManager(flashlightManager)
    , m_modemManager(modemManager)
    , m_settingsManager(settingsManager)
    , m_alarmManager(alarmManager)
    , m_locationManager(locationManager)
    , m_hapticManager(hapticManager)
    , m_powerManager(powerManager)
    , m_audioManager(audioManager)
    , m_audioPolicyController(audioPolicyController)
    , m_screenshotService(screenshotService) {
    if (m_networkManager) {
        setIsWifiOn(m_networkManager->getWifiEnabled());
        setIsAirplaneModeOn(m_networkManager->getAirplaneModeEnabled());
        setIsHotspotOn(m_networkManager->isHotspotActive());
        connect(m_networkManager, &Network::hotspotActiveChanged, this,
                [this]() { setIsHotspotOn(m_networkManager->isHotspotActive()); });
        connect(m_networkManager, &Network::hotspotFailed, this,
                [this](const QString &message) {
                    clearPending(QStringLiteral("hotspot"));
                    emit hotspotFailed(message);
                });
        connect(m_networkManager, &Network::wifiEnabledChanged, this,
                [this]() { setIsWifiOn(m_networkManager->getWifiEnabled()); });
        connect(m_networkManager, &Network::airplaneModeEnabledChanged, this,
                [this]() { setIsAirplaneModeOn(m_networkManager->getAirplaneModeEnabled()); });
    }

    if (m_bluetoothManager) {
        connect(m_bluetoothManager, &Bluetooth::enabledChanged, this, [this]() {
            clearPending(QStringLiteral("bluetooth"));
            emit isBluetoothOnChanged();
        });
    }

    if (m_display) {
        setIsRotationLocked(m_display->getRotationLocked());
        setIsAutoBrightnessOn(m_display->getAutoBrightness());
        setIsNightLightOn(m_display->getNightLightEnabled());
        setBrightnessValue(static_cast<int>(
            std::round(std::clamp(m_display->getBrightness(), 0.0, 1.0) * 100.0)));
        connect(m_display, &marathon::Display::rotationLockedChanged, this,
                [this]() { setIsRotationLocked(m_display->getRotationLocked()); });
        connect(m_display, &marathon::Display::autoBrightnessChanged, this,
                [this]() { setIsAutoBrightnessOn(m_display->getAutoBrightness()); });
        connect(m_display, &marathon::Display::nightLightEnabledChanged, this,
                [this]() { setIsNightLightOn(m_display->getNightLightEnabled()); });
        connect(m_display, &marathon::Display::brightnessChanged, this, [this]() {
            setBrightnessValue(static_cast<int>(
                std::round(std::clamp(m_display->getBrightness(), 0.0, 1.0) * 100.0)));
        });
    }

    if (m_flashlightManager) {
        setIsFlashlightOn(m_flashlightManager->getEnabled());
        connect(m_flashlightManager, &Flashlight::enabledChanged, this,
                [this]() { setIsFlashlightOn(m_flashlightManager->getEnabled()); });
    }

    if (m_modemManager) {
        setIsCellularOn(m_modemManager->getModemEnabled());
        setIsCellularDataOn(m_modemManager->getDataEnabled());
        connect(m_modemManager, &Modem::modemEnabledChanged, this,
                [this]() { setIsCellularOn(m_modemManager->getModemEnabled()); });
        connect(m_modemManager, &Modem::dataEnabledChanged, this,
                [this]() { setIsCellularDataOn(m_modemManager->getDataEnabled()); });
    }

    if (m_settingsManager) {
        setIsDndMode(m_settingsManager->getDndEnabled());
        connect(m_settingsManager, &marathon::Settings::dndEnabledChanged, this,
                [this]() { setIsDndMode(m_settingsManager->getDndEnabled()); });
    }

    if (m_alarmManager) {
        refreshAlarmState();
        connect(m_alarmManager, &Alarms::alarmsChanged, this,
                [this]() { refreshAlarmState(); });
        connect(m_alarmManager, &Alarms::activeAlarmsChanged, this,
                [this]() { refreshAlarmState(); });
    }

    if (m_locationManager) {
        setIsLocationOn(m_locationManager->getActive());
        connect(m_locationManager, &Location::activeChanged, this,
                [this]() { setIsLocationOn(m_locationManager->getActive()); });
    }

    if (m_hapticManager) {
        setIsVibrationOn(m_hapticManager->getEnabled());
        connect(m_hapticManager, &Haptics::enabledChanged, this,
                [this]() { setIsVibrationOn(m_hapticManager->getEnabled()); });
    }

    if (m_powerManager) {
        setIsLowPowerMode(m_powerManager->getIsPowerSaveMode());
        connect(m_powerManager, &Power::isPowerSaveModeChanged, this,
                [this]() { setIsLowPowerMode(m_powerManager->getIsPowerSaveMode()); });
    }

    if (m_audioManager) {
        setVolumeValue(
            static_cast<int>(std::round(std::clamp(m_audioManager->getVolume(), 0.0, 1.0) * 100.0)));
        connect(m_audioManager, &marathon::Audio::volumeChanged, this, [this]() {
            setVolumeValue(static_cast<int>(
                std::round(std::clamp(m_audioManager->getVolume(), 0.0, 1.0) * 100.0)));
        });
    }
}

// Cleared by the backend's state change, or after 10 s if it never comes.
void SystemControlStore::markPending(const QString &id) {
    const int serial      = ++m_nextPendingSerial;
    m_pendingSerial[id] = serial;
    if (!m_pendingSwitches.contains(id)) {
        m_pendingSwitches.append(id);
        emit pendingSwitchesChanged();
    }
    QTimer::singleShot(10000, this, [this, id, serial]() {
        if (m_pendingSerial.value(id) == serial)
            clearPending(id);
    });
}

void SystemControlStore::clearPending(const QString &id) {
    m_pendingSerial.remove(id);
    if (m_pendingSwitches.removeAll(id) > 0)
        emit pendingSwitchesChanged();
}

void SystemControlStore::toggleWifi() {
    if (m_networkManager) {
        markPending(QStringLiteral("wifi"));
        m_networkManager->toggleWifi();
    }
}

bool SystemControlStore::isBluetoothOn() const {
    return m_bluetoothManager ? m_bluetoothManager->getEnabled() : false;
}

int SystemControlStore::brightness() const {
    // Live-read so we don't ship a cached 0% that was captured before
    // the backlight device finished probing. Same passthrough pattern
    // as isBluetoothOn().
    if (!m_display)
        return 0;
    return static_cast<int>(
        std::round(std::clamp(m_display->getBrightness(), 0.0, 1.0) * 100.0));
}

void SystemControlStore::toggleBluetooth() {
    if (m_bluetoothManager) {
        markPending(QStringLiteral("bluetooth"));
        m_bluetoothManager->setEnabled(!m_bluetoothManager->getEnabled());
    }
}

void SystemControlStore::toggleAirplaneMode() {
    if (m_networkManager) {
        m_networkManager->setAirplaneMode(!m_isAirplaneModeOn);
    }
}

void SystemControlStore::toggleRotationLock() {
    if (m_display) {
        m_display->setRotationLocked(!m_isRotationLocked);
    }
}

void SystemControlStore::toggleFlashlight() {
    if (m_flashlightManager) {
        m_flashlightManager->toggle();
    }
}

void SystemControlStore::toggleCellularData() {
    if (!m_modemManager) {
        return;
    }
    markPending(QStringLiteral("cellular"));
    if (m_modemManager->getDataEnabled()) {
        m_modemManager->disableData();
    } else {
        m_modemManager->enableData();
    }
}

void SystemControlStore::toggleDndMode() {
    const bool enable = !m_isDndMode;
    if (m_settingsManager) {
        m_settingsManager->setDndEnabled(enable);
    }
    if (m_audioPolicyController) {
        m_audioPolicyController->setDoNotDisturb(enable);
    }
}

void SystemControlStore::toggleLowPowerMode() {
    if (m_powerManager) {
        m_powerManager->setPowerSaveMode(!m_isLowPowerMode);
    }
}

void SystemControlStore::toggleAutoBrightness() {
    if (m_display) {
        m_display->setAutoBrightness(!m_isAutoBrightnessOn);
    }
}

void SystemControlStore::toggleLocation() {
    if (!m_locationManager) {
        return;
    }
    markPending(QStringLiteral("location"));
    if (m_isLocationOn) {
        m_locationManager->stop();
    } else {
        m_locationManager->start();
    }
}

void SystemControlStore::toggleHotspot() {
    if (!m_networkManager) {
        return;
    }
    markPending(QStringLiteral("hotspot"));
    if (m_networkManager->isHotspotActive()) {
        m_networkManager->stopHotspot();
    } else {
        ensureHotspotCredentials();
        m_networkManager->createHotspot(m_hotspotSsid, m_hotspotPassword);
    }
}

// Generated once per device and kept, so clients that joined stay joined.
void SystemControlStore::ensureHotspotCredentials() {
    if (!m_hotspotPassword.isEmpty())
        return;
    if (m_settingsManager) {
        m_hotspotSsid     = m_settingsManager->get("hotspot/ssid", QVariant()).toString();
        m_hotspotPassword = m_settingsManager->get("hotspot/password", QVariant()).toString();
    }
    if (m_hotspotPassword.isEmpty()) {
        // No 0/O/1/l/i: the password is read off the screen and typed.
        static const QString kAlphabet = QStringLiteral("abcdefghjkmnpqrstuvwxyz23456789");
        QRandomGenerator    *rng       = QRandomGenerator::system();
        auto                 pick      = [rng](int n) {
            QString s;
            for (int i = 0; i < n; ++i)
                s += kAlphabet.at(static_cast<int>(rng->bounded(kAlphabet.size())));
            return s;
        };
        m_hotspotSsid     = QStringLiteral("Marathon-") + pick(4).toUpper();
        m_hotspotPassword = pick(4) + '-' + pick(4) + '-' + pick(4);
        if (m_settingsManager) {
            m_settingsManager->set("hotspot/ssid", m_hotspotSsid);
            m_settingsManager->set("hotspot/password", m_hotspotPassword);
            m_settingsManager->sync();
        }
    }
    emit hotspotCredentialsChanged();
}

void SystemControlStore::toggleVibration() {
    if (m_hapticManager) {
        m_hapticManager->setEnabled(!m_isVibrationOn);
    }
}

void SystemControlStore::toggleNightLight() {
    if (m_display) {
        m_display->setNightLightEnabled(!m_isNightLightOn);
    }
}

void SystemControlStore::captureScreenshot() {
    if (m_screenshotService) {
        m_screenshotService->captureScreen();
    }
}

void SystemControlStore::setBrightness(int value) {
    int clamped = std::clamp(value, 0, 100);
    if (m_display) {
        m_display->setBrightness(static_cast<double>(clamped) / 100.0);
    }
    setBrightnessValue(clamped);
}

void SystemControlStore::setBrightnessFromUser(int value) {
    int clamped = std::clamp(value, 0, 100);
    if (m_display) {
        // Routes through the learning path so the adaptive curve is taught;
        // the plain setBrightness above stays silent for idle-dim/programmatic.
        m_display->setBrightnessFromUser(static_cast<double>(clamped) / 100.0);
    }
    setBrightnessValue(clamped);
    emit userBrightnessChanged(clamped);
}

void SystemControlStore::setVolume(int value) {
    int clamped = std::clamp(value, 0, 100);
    if (m_audioManager) {
        m_audioManager->setVolume(static_cast<double>(clamped) / 100.0);
    } else if (m_audioPolicyController) {
        m_audioPolicyController->setMasterVolume(static_cast<double>(clamped) / 100.0);
    }
    setVolumeValue(clamped);
}

void SystemControlStore::sleep() {
    if (m_powerManager) {
        m_powerManager->suspend();
    }
}

void SystemControlStore::reboot() {
    if (m_powerManager) {
        m_powerManager->restart();
    }
}

void SystemControlStore::setIsWifiOn(bool enabled) {
    clearPending(QStringLiteral("wifi"));
    if (m_isWifiOn == enabled) {
        return;
    }
    m_isWifiOn = enabled;
    emit isWifiOnChanged();
}

void SystemControlStore::setIsAirplaneModeOn(bool enabled) {
    if (m_isAirplaneModeOn == enabled) {
        return;
    }
    m_isAirplaneModeOn = enabled;
    emit isAirplaneModeOnChanged();
}

void SystemControlStore::setIsRotationLocked(bool enabled) {
    if (m_isRotationLocked == enabled) {
        return;
    }
    m_isRotationLocked = enabled;
    emit isRotationLockedChanged();
}

void SystemControlStore::setIsFlashlightOn(bool enabled) {
    if (m_isFlashlightOn == enabled) {
        return;
    }
    m_isFlashlightOn = enabled;
    emit isFlashlightOnChanged();
}

void SystemControlStore::setIsCellularOn(bool enabled) {
    if (m_isCellularOn == enabled) {
        return;
    }
    m_isCellularOn = enabled;
    emit isCellularOnChanged();
}

void SystemControlStore::setIsCellularDataOn(bool enabled) {
    clearPending(QStringLiteral("cellular"));
    if (m_isCellularDataOn == enabled) {
        return;
    }
    m_isCellularDataOn = enabled;
    emit isCellularDataOnChanged();
}

void SystemControlStore::setIsDndMode(bool enabled) {
    if (m_isDndMode == enabled) {
        return;
    }
    m_isDndMode = enabled;
    emit isDndModeChanged();
}

void SystemControlStore::setIsAlarmOn(bool enabled) {
    if (m_isAlarmOn == enabled) {
        return;
    }
    m_isAlarmOn = enabled;
    emit isAlarmOnChanged();
}

void SystemControlStore::setIsAutoBrightnessOn(bool enabled) {
    if (m_isAutoBrightnessOn == enabled) {
        return;
    }
    m_isAutoBrightnessOn = enabled;
    emit isAutoBrightnessOnChanged();
}

void SystemControlStore::setIsLocationOn(bool enabled) {
    clearPending(QStringLiteral("location"));
    if (m_isLocationOn == enabled) {
        return;
    }
    m_isLocationOn = enabled;
    emit isLocationOnChanged();
}

void SystemControlStore::setIsHotspotOn(bool enabled) {
    clearPending(QStringLiteral("hotspot"));
    if (m_isHotspotOn == enabled) {
        return;
    }
    m_isHotspotOn = enabled;
    emit isHotspotOnChanged();
}

void SystemControlStore::setIsVibrationOn(bool enabled) {
    if (m_isVibrationOn == enabled) {
        return;
    }
    m_isVibrationOn = enabled;
    emit isVibrationOnChanged();
}

void SystemControlStore::setIsNightLightOn(bool enabled) {
    if (m_isNightLightOn == enabled) {
        return;
    }
    m_isNightLightOn = enabled;
    emit isNightLightOnChanged();
}

void SystemControlStore::setBrightnessValue(int value) {
    if (m_brightness == value) {
        return;
    }
    m_brightness = value;
    emit brightnessChanged();
}

void SystemControlStore::setVolumeValue(int value) {
    if (m_volume == value) {
        return;
    }
    m_volume = value;
    emit volumeChanged();
}

void SystemControlStore::setIsLowPowerMode(bool enabled) {
    if (m_isLowPowerMode == enabled) {
        return;
    }
    m_isLowPowerMode = enabled;
    emit isLowPowerModeChanged();
}

void SystemControlStore::refreshAlarmState() {
    if (!m_alarmManager) {
        setIsAlarmOn(false);
        return;
    }
    setIsAlarmOn(m_alarmManager->getHasActiveAlarm() || m_alarmManager->getHasEnabledAlarm());
}
