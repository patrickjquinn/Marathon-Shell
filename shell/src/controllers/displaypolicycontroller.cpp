#include "displaypolicycontroller.h"

#include "displaymanagercpp.h"
#include "settingsmanager.h"

#include <QtMath>

DisplayPolicyController::DisplayPolicyController(DisplayManagerCpp *displayManager,
                                                 SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , m_displayManager(displayManager)
    , m_settingsManager(settingsManager) {

    if (m_settingsManager) {
        connect(m_settingsManager, &SettingsManager::screenTimeoutChanged, this, [this]() {
            emit screenTimeoutMsChanged();

            if (m_displayManager)
                m_displayManager->setScreenTimeout(
                    qMax(0, m_settingsManager->screenTimeout() / 1000));
        });

        connect(m_settingsManager, &SettingsManager::autoBrightnessChanged, this, [this]() {
            if (m_displayManager)
                m_displayManager->setAutoBrightness(m_settingsManager->autoBrightness());
            emit autoBrightnessEnabledChanged();
        });
    }

    if (m_displayManager) {
        connect(m_displayManager, &DisplayManagerCpp::autoBrightnessEnabledChanged, this, [this]() {
            if (m_settingsManager &&
                m_settingsManager->autoBrightness() != m_displayManager->autoBrightnessEnabled())
                m_settingsManager->setAutoBrightness(m_displayManager->autoBrightnessEnabled());
            emit autoBrightnessEnabledChanged();
        });

        connect(m_displayManager, &DisplayManagerCpp::screenStateChanged, this, [this](bool on) {
            if (m_screenOn == on)
                return;
            m_screenOn = on;
            emit screenOnChanged();
        });
    }
}

int DisplayPolicyController::screenTimeoutMs() const {
    if (m_settingsManager)
        return m_settingsManager->screenTimeout();
    return 120000;
}

void DisplayPolicyController::setScreenTimeoutMs(int ms) {
    ms = qMax(0, ms);
    if (m_settingsManager && m_settingsManager->screenTimeout() != ms)
        m_settingsManager->setScreenTimeout(ms);

    if (m_displayManager)
        m_displayManager->setScreenTimeout(qMax(0, ms / 1000));

    emit screenTimeoutMsChanged();
}

QString DisplayPolicyController::screenTimeoutString() const {
    const int ms = screenTimeoutMs();
    if (ms == 0)
        return "Never";

    if (ms < 60000)
        return QString("%1 seconds").arg(qRound(ms / 1000.0));

    if (ms < 3600000) {
        const int minutes = qRound(ms / 60000.0);
        return QString("%1 minute%2").arg(minutes).arg(minutes > 1 ? "s" : "");
    }

    const int hours = qRound(ms / 3600000.0);
    return QString("%1 hour%2").arg(hours).arg(hours > 1 ? "s" : "");
}

bool DisplayPolicyController::autoBrightnessEnabled() const {
    if (m_displayManager)
        return m_displayManager->autoBrightnessEnabled();
    if (m_settingsManager)
        return m_settingsManager->autoBrightness();
    return false;
}

void DisplayPolicyController::setAutoBrightnessEnabled(bool enabled) {
    if (m_displayManager)
        m_displayManager->setAutoBrightness(enabled);
    if (m_settingsManager && m_settingsManager->autoBrightness() != enabled)
        m_settingsManager->setAutoBrightness(enabled);
    emit autoBrightnessEnabledChanged();
}

void DisplayPolicyController::turnScreenOn() {
    if (m_displayManager)
        m_displayManager->setScreenState(true);
    if (!m_screenOn) {
        m_screenOn = true;
        emit screenOnChanged();
    }
}

void DisplayPolicyController::turnScreenOff() {
    if (m_displayManager)
        m_displayManager->setScreenState(false);
    if (m_screenOn) {
        m_screenOn = false;
        emit screenOnChanged();
    }
}
