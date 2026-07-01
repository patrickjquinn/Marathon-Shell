#include "powerbatteryhandlercpp.h"

#include "displaymanagercpp.h"
#include "displaypolicycontroller.h"
#include "hapticmanager.h"
#include "powerpolicycontroller.h"

#include <QDateTime>

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

    // A single physical power press fans out to TWO handlers — QML
    // Keys.onReleased (when the shell has focus) and PowerKeyListener
    // (raw /dev/input) — which must be coalesced to one action. The
    // second one is DELAYED by the compositor doze/resume transition:
    // with the deep-idle display-off (CRTC ACTIVE=0 + releaseResources +
    // DDR downshift) it lands 265-402ms after the first (measured on
    // L5), past the old 200ms window, where it sees screenOn already
    // flipped and REVERSES the action — the "screen turns off then back
    // on" bug (and its mirror, "won't wake"). An 800ms window covers the
    // transition with margin under load while staying well under any
    // intentional double-press of the power button.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastPressMs < 800) {
        // Second event source firing for the same physical press. Ignore.
        return;
    }
    m_lastPressMs = now;

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
