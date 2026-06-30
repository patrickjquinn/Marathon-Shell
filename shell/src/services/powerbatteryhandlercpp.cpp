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
    // Route through Doze exit when available — that path (a) re-syncs
    // m_screenOn via DisplayPolicyController::forceScreenOn semantics,
    // (b) re-writes brightness to defeat the i.MX 8M PWM glitch
    // (r293), and (c) thaws background apps' freeze debounce. Plain
    // displayPolicy->turnScreenOn() is fine if PowerPolicy isn't
    // wired (early boot path).
    if (m_powerPolicy && m_powerPolicy->dozing()) {
        m_powerPolicy->exitDoze();
        return;
    }
    if (m_displayPolicy)
        m_displayPolicy->turnScreenOn();
    else if (m_displayManager)
        m_displayManager->setScreenState(true);
}

void PowerBatteryHandlerCpp::turnScreenOff() {
    // Route through Doze entry when available — that path freezes
    // background apps immediately + flips wifi PSM on, so the
    // backlight-off state is actually low-power and push connections
    // survive. Falls back to a plain backlight blank if PowerPolicy
    // isn't wired.
    if (m_powerPolicy) {
        m_powerPolicy->enterDoze();
        return;
    }
    if (m_displayPolicy)
        m_displayPolicy->turnScreenOff();
    else if (m_displayManager)
        m_displayManager->setScreenState(false);
}
