pragma Singleton
import QtQuick
import MarathonOS.Shell

Item {
    id: proximitySensor

    property bool available: SensorManagerCpp.available
    property bool active: true
    property bool near: SensorManagerCpp.proximityNear
    property real distance: near ? 0 : 100

    property bool autoScreenOff: true // Auto turn off screen when near

    signal proximityChanged(bool near)

    Connections {
        target: SensorManagerCpp
        function onProximityNearChanged() {
            near = SensorManagerCpp.proximityNear
            distance = near ? 0 : 100

            Logger.info("ProximitySensor", "NEAR = " + near)

            proximityChanged(near)

            if (autoScreenOff && typeof TelephonyManager !== "undefined" && TelephonyManager.hasActiveCall) {
                if (near && DisplayManager.screenOn) {
                    Logger.info("ProximitySensor", "Auto screen OFF (during call)")
                    DisplayManager.turnScreenOff()
                } else if (!near && !DisplayManager.screenOn) {
                    Logger.info("ProximitySensor", "Auto screen ON (away from face)")
                    DisplayManager.turnScreenOn()
                }
            }
        }
    }

    Component.onCompleted: {
        Logger.info("ProximitySensor", "Initialized (QtSensors)")
    }
}
