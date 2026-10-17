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

        // Initial sync — SettingsManager is the source of truth and may
        // already have auto-brightness ON at boot, in which case the
        // changed signal never fires and DisplayManager would otherwise
        // never enable the ambient-light engine.
        if (m_displayManager) {
            m_displayManager->setAutoBrightness(m_settingsManager->autoBrightness());
            m_displayManager->setScreenTimeout(qMax(0, m_settingsManager->screenTimeout() / 1000));
        }
    }

    if (m_displayManager) {
        connect(m_displayManager, &DisplayManagerCpp::autoBrightnessEnabledChanged, this, [this]() {
            if (m_settingsManager &&
                m_settingsManager->autoBrightness() != m_displayManager->autoBrightnessEnabled())
                m_settingsManager->setAutoBrightness(m_displayManager->autoBrightnessEnabled());
            emit autoBrightnessEnabledChanged();
        });

        connect(m_displayManager, &DisplayManagerCpp::screenOnChanged, this,
                &DisplayPolicyController::screenOnChanged);
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

bool DisplayPolicyController::screenOn() const {
    return !m_displayManager || m_displayManager->screenOn();
}

void DisplayPolicyController::turnScreenOn() {
    if (m_displayManager)
        m_displayManager->setScreenState(true);
}

void DisplayPolicyController::turnScreenOff(const QString &reason) {
    if (m_displayManager)
        m_displayManager->setScreenState(false, reason);
}

void DisplayPolicyController::forceScreenOn() {
    const bool wasOn = screenOn();
    if (m_displayManager)
        m_displayManager->setScreenState(true);
    // The resume edge is a wake even when the screen never read off.
    if (wasOn)
        emit screenOnChanged();
}
