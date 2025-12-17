pragma Singleton
import MarathonOS.Shell
import QtQuick

QtObject {
    id: root

    function handlePowerButtonPress() {
        if (typeof PowerPolicyControllerCpp === "undefined" || !PowerPolicyControllerCpp)
            return;

        var screenOn = (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenOn : DisplayManager.screenOn;
        var isLocked = SessionStore.isLocked;
        var action = PowerPolicyControllerCpp.powerButtonAction(screenOn, isLocked);
        if (action === PowerPolicyControllerCpp.TurnScreenOn) {
            DisplayManager.turnScreenOn();
        } else if (action === PowerPolicyControllerCpp.LockAndTurnScreenOff) {
            SessionStore.lock();
            DisplayManager.turnScreenOff();
        } else if (action === PowerPolicyControllerCpp.TurnScreenOff) {
            DisplayManager.turnScreenOff();
        }
        if (typeof HapticService !== "undefined" && HapticService)
            HapticService.medium();
    }
}
