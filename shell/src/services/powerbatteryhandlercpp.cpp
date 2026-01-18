#include "powerbatteryhandlercpp.h"

#include "displaymanagercpp.h"
#include "displaypolicycontroller.h"
#include "hapticmanager.h"
#include "powerpolicycontroller.h"

PowerBatteryHandlerCpp::PowerBatteryHandlerCpp(PowerPolicyController   *powerPolicy,
                                               DisplayPolicyController *displayPolicy,
                                               DisplayManagerCpp       *displayManager,
                                               HapticManager *haptics, QObject *parent)
    : QObject(parent)
    , m_powerPolicy(powerPolicy)
    , m_displayPolicy(displayPolicy)
    , m_displayManager(displayManager)
    , m_haptics(haptics) {}

void PowerBatteryHandlerCpp::handlePowerButtonPress(bool sessionLocked, bool screenOnHint) {
    if (!m_powerPolicy)
        return;

    const bool screenOn = m_displayPolicy ? m_displayPolicy->screenOn() : screenOnHint;
    const auto action   = m_powerPolicy->powerButtonAction(screenOn, sessionLocked);

    if (action == PowerPolicyController::TurnScreenOn) {
        turnScreenOn();
    } else if (action == PowerPolicyController::LockAndTurnScreenOff) {
        emit lockRequested();
        turnScreenOff();
    } else if (action == PowerPolicyController::TurnScreenOff) {
        turnScreenOff();
    }

    if (m_haptics)
        m_haptics->medium();
}

void PowerBatteryHandlerCpp::turnScreenOn() {
    if (m_displayPolicy)
        m_displayPolicy->turnScreenOn();
    else if (m_displayManager)
        m_displayManager->setScreenState(true);
}

void PowerBatteryHandlerCpp::turnScreenOff() {
    if (m_displayPolicy)
        m_displayPolicy->turnScreenOff();
    else if (m_displayManager)
        m_displayManager->setScreenState(false);
}
