pragma Singleton
import MarathonOS.Shell
import QtQuick

Item {
    id: proximitySensor

    property bool available: SensorManagerCpp.available
    property bool active: true
    property bool near: SensorManagerCpp.proximityNear
    property real distance: near ? 0 : 100
    property bool autoScreenOff: true // Auto turn off screen when near

    signal proximityChanged(bool near)

    Component.onCompleted: {
        Logger.info("ProximitySensor", "Initialized (QtSensors)");
    }

    Connections {
        function onProximityNearChanged() {
            near = SensorManagerCpp.proximityNear;
            distance = near ? 0 : 100;
            Logger.info("ProximitySensor", "NEAR = " + near);
            proximityChanged(near);
            if (autoScreenOff && typeof TelephonyIntegration !== "undefined" && TelephonyIntegration.hasActiveCall) {
                var screenOn = (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenOn : true;
                if (near && screenOn) {
                    Logger.info("ProximitySensor", "Auto screen OFF (during call)");
                    if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                        DisplayPolicyControllerCpp.turnScreenOff();
                    else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                        DisplayManagerCpp.setScreenState(false);
                } else if (!near && !screenOn) {
                    Logger.info("ProximitySensor", "Auto screen ON (away from face)");
                    if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                        DisplayPolicyControllerCpp.turnScreenOn();
                    else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                        DisplayManagerCpp.setScreenState(true);
                }
            }
        }

        target: SensorManagerCpp
    }
}
