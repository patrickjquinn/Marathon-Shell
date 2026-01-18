#include "systemcontrolstore.h"
#include "src/controllers/audiopolicycontroller.h"
#include "src/managers/alarmmanagercpp.h"
#include "src/managers/audiomanagercpp.h"
#include "src/managers/bluetoothmanager.h"
#include "src/managers/displaymanagercpp.h"
#include "src/managers/flashlightmanagercpp.h"
#include "src/managers/hapticmanager.h"
#include "src/managers/locationmanager.h"
#include "src/managers/modemmanagercpp.h"
#include "src/managers/networkmanagercpp.h"
#include "src/managers/powermanagercpp.h"
#include "src/managers/settingsmanager.h"
#include "src/services/screenshotservicecpp.h"
#include <cmath>
#include <algorithm>

SystemControlStore::SystemControlStore(
    NetworkManagerCpp *networkManager, BluetoothManager *bluetoothManager,
    DisplayManagerCpp *displayManager, FlashlightManagerCpp *flashlightManager,
    ModemManagerCpp *modemManager, SettingsManager *settingsManager, AlarmManagerCpp *alarmManager,
    LocationManager *locationManager, HapticManager *hapticManager, PowerManagerCpp *powerManager,
    AudioManagerCpp *audioManager, AudioPolicyController *audioPolicyController,
    ScreenshotServiceCpp *screenshotService, QObject *parent)
    : QObject(parent)
    , m_networkManager(networkManager)
    , m_bluetoothManager(bluetoothManager)
    , m_displayManager(displayManager)
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
        setIsWifiOn(m_networkManager->wifiEnabled());
        setIsAirplaneModeOn(m_networkManager->airplaneModeEnabled());
        setIsHotspotOn(m_networkManager->isHotspotActive());
        connect(m_networkManager, &NetworkManagerCpp::wifiEnabledChanged, this,
                [this]() { setIsWifiOn(m_networkManager->wifiEnabled()); });
        connect(m_networkManager, &NetworkManagerCpp::airplaneModeEnabledChanged, this,
                [this]() { setIsAirplaneModeOn(m_networkManager->airplaneModeEnabled()); });
    }

    if (m_bluetoothManager) {
        setIsBluetoothOn(m_bluetoothManager->enabled());
        connect(m_bluetoothManager, &BluetoothManager::enabledChanged, this,
                [this]() { setIsBluetoothOn(m_bluetoothManager->enabled()); });
    }

    if (m_displayManager) {
        setIsRotationLocked(m_displayManager->rotationLocked());
        setIsAutoBrightnessOn(m_displayManager->autoBrightnessEnabled());
        setIsNightLightOn(m_displayManager->nightLightEnabled());
        setBrightnessValue(static_cast<int>(
            std::round(std::clamp(m_displayManager->brightness(), 0.0, 1.0) * 100.0)));
        connect(m_displayManager, &DisplayManagerCpp::rotationLockedChanged, this,
                [this]() { setIsRotationLocked(m_displayManager->rotationLocked()); });
        connect(m_displayManager, &DisplayManagerCpp::autoBrightnessEnabledChanged, this,
                [this]() { setIsAutoBrightnessOn(m_displayManager->autoBrightnessEnabled()); });
        connect(m_displayManager, &DisplayManagerCpp::nightLightEnabledChanged, this,
                [this]() { setIsNightLightOn(m_displayManager->nightLightEnabled()); });
        connect(m_displayManager, &DisplayManagerCpp::brightnessChanged, this, [this]() {
            setBrightnessValue(static_cast<int>(
                std::round(std::clamp(m_displayManager->brightness(), 0.0, 1.0) * 100.0)));
        });
    }

    if (m_flashlightManager) {
        setIsFlashlightOn(m_flashlightManager->enabled());
        connect(m_flashlightManager, &FlashlightManagerCpp::enabledChanged, this,
                [this]() { setIsFlashlightOn(m_flashlightManager->enabled()); });
    }

    if (m_modemManager) {
        setIsCellularOn(m_modemManager->modemEnabled());
        setIsCellularDataOn(m_modemManager->dataEnabled());
        connect(m_modemManager, &ModemManagerCpp::modemEnabledChanged, this,
                [this]() { setIsCellularOn(m_modemManager->modemEnabled()); });
        connect(m_modemManager, &ModemManagerCpp::dataEnabledChanged, this,
                [this]() { setIsCellularDataOn(m_modemManager->dataEnabled()); });
    }

    if (m_settingsManager) {
        setIsDndMode(m_settingsManager->dndEnabled());
        connect(m_settingsManager, &SettingsManager::dndEnabledChanged, this,
                [this]() { setIsDndMode(m_settingsManager->dndEnabled()); });
    }

    if (m_alarmManager) {
        refreshAlarmState();
        connect(m_alarmManager, &AlarmManagerCpp::alarmsChanged, this,
                [this]() { refreshAlarmState(); });
        connect(m_alarmManager, &AlarmManagerCpp::activeAlarmsChanged, this,
                [this]() { refreshAlarmState(); });
    }

    if (m_locationManager) {
        setIsLocationOn(m_locationManager->active());
        connect(m_locationManager, &LocationManager::activeChanged, this,
                [this]() { setIsLocationOn(m_locationManager->active()); });
    }

    if (m_hapticManager) {
        setIsVibrationOn(m_hapticManager->enabled());
        connect(m_hapticManager, &HapticManager::enabledChanged, this,
                [this]() { setIsVibrationOn(m_hapticManager->enabled()); });
    }

    if (m_powerManager) {
        setIsLowPowerMode(m_powerManager->isPowerSaveMode());
        connect(m_powerManager, &PowerManagerCpp::isPowerSaveModeChanged, this,
                [this]() { setIsLowPowerMode(m_powerManager->isPowerSaveMode()); });
    }

    if (m_audioManager) {
        setVolumeValue(
            static_cast<int>(std::round(std::clamp(m_audioManager->volume(), 0.0, 1.0) * 100.0)));
        connect(m_audioManager, &AudioManagerCpp::volumeChanged, this, [this]() {
            setVolumeValue(static_cast<int>(
                std::round(std::clamp(m_audioManager->volume(), 0.0, 1.0) * 100.0)));
        });
    }
}

void SystemControlStore::toggleWifi() {
    if (m_networkManager) {
        m_networkManager->toggleWifi();
    }
}

void SystemControlStore::toggleBluetooth() {
    if (m_bluetoothManager) {
        m_bluetoothManager->setEnabled(!m_bluetoothManager->enabled());
    }
}

void SystemControlStore::toggleAirplaneMode() {
    if (m_networkManager) {
        m_networkManager->setAirplaneMode(!m_isAirplaneModeOn);
    }
}

void SystemControlStore::toggleRotationLock() {
    if (m_displayManager) {
        m_displayManager->setRotationLock(!m_isRotationLocked);
    }
}

void SystemControlStore::toggleFlashlight() {
    if (m_flashlightManager) {
        m_flashlightManager->toggle();
    }
}

void SystemControlStore::toggleCellular() {
    if (!m_modemManager) {
        return;
    }
    if (m_modemManager->modemEnabled()) {
        m_modemManager->disable();
    } else {
        m_modemManager->enable();
    }
}

void SystemControlStore::toggleCellularData() {
    if (!m_modemManager) {
        return;
    }
    if (m_modemManager->dataEnabled()) {
        m_modemManager->disableData();
    } else {
        m_modemManager->enableData();
    }
}

void SystemControlStore::toggleDndMode() {
    if (m_settingsManager) {
        m_settingsManager->setDndEnabled(!m_isDndMode);
    }
    if (m_audioPolicyController) {
        m_audioPolicyController->setDoNotDisturb(!m_isDndMode);
    }
}

void SystemControlStore::toggleAlarm() {}

void SystemControlStore::toggleLowPowerMode() {
    if (m_powerManager) {
        m_powerManager->setPowerSaveMode(!m_isLowPowerMode);
    }
}

void SystemControlStore::toggleAutoBrightness() {
    if (m_displayManager) {
        m_displayManager->setAutoBrightness(!m_isAutoBrightnessOn);
    }
}

void SystemControlStore::toggleLocation() {
    if (!m_locationManager) {
        return;
    }
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
    if (m_networkManager->isHotspotActive()) {
        m_networkManager->stopHotspot();
        setIsHotspotOn(false);
    } else {
        m_networkManager->createHotspot("Marathon Hotspot", "marathon2025");
        setIsHotspotOn(true);
    }
}

void SystemControlStore::toggleVibration() {
    if (m_hapticManager) {
        m_hapticManager->setEnabled(!m_isVibrationOn);
    }
}

void SystemControlStore::toggleNightLight() {
    if (m_displayManager) {
        m_displayManager->setNightLightEnabled(!m_isNightLightOn);
    }
}

void SystemControlStore::captureScreenshot() {
    if (m_screenshotService) {
        m_screenshotService->captureScreen();
    }
}

void SystemControlStore::setBrightness(int value) {
    int clamped = std::clamp(value, 0, 100);
    if (m_displayManager) {
        m_displayManager->setBrightness(static_cast<double>(clamped) / 100.0);
    }
    setBrightnessValue(clamped);
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

void SystemControlStore::powerOff() {
    if (m_powerManager) {
        m_powerManager->shutdown();
    }
}

void SystemControlStore::reboot() {
    if (m_powerManager) {
        m_powerManager->restart();
    }
}

void SystemControlStore::setIsWifiOn(bool enabled) {
    if (m_isWifiOn == enabled) {
        return;
    }
    m_isWifiOn = enabled;
    emit isWifiOnChanged();
}

void SystemControlStore::setIsBluetoothOn(bool enabled) {
    if (m_isBluetoothOn == enabled) {
        return;
    }
    m_isBluetoothOn = enabled;
    emit isBluetoothOnChanged();
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
    if (m_isLocationOn == enabled) {
        return;
    }
    m_isLocationOn = enabled;
    emit isLocationOnChanged();
}

void SystemControlStore::setIsHotspotOn(bool enabled) {
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
    setIsAlarmOn(m_alarmManager->hasActiveAlarm() || m_alarmManager->hasEnabledAlarm());
}
