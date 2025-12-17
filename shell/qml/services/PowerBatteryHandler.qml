pragma Singleton
import MarathonOS.Shell
import QtQuick

QtObject {
    id: root

    function handlePowerButtonPress() {
        if (typeof PowerPolicyControllerCpp === "undefined" || !PowerPolicyControllerCpp)
            return;

        var screenOn = (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenOn : true;
        var isLocked = SessionStore.isLocked;
        var action = PowerPolicyControllerCpp.powerButtonAction(screenOn, isLocked);
        if (action === PowerPolicyControllerCpp.TurnScreenOn) {
            if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                DisplayPolicyControllerCpp.turnScreenOn();
            else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                DisplayManagerCpp.setScreenState(true);
        } else if (action === PowerPolicyControllerCpp.LockAndTurnScreenOff) {
            SessionStore.lock();
            if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                DisplayPolicyControllerCpp.turnScreenOff();
            else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                DisplayManagerCpp.setScreenState(false);
        } else if (action === PowerPolicyControllerCpp.TurnScreenOff) {
            if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                DisplayPolicyControllerCpp.turnScreenOff();
            else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                DisplayManagerCpp.setScreenState(false);
        }
        if (typeof HapticService !== "undefined" && HapticService)
            HapticService.medium();
    }
}
