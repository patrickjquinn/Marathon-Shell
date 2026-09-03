import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

Item {
    id: connectionToast

    property string message: ""
    property string iconName: "wifi"
    property bool showing: false
    property bool initialized: false

    function show(msg, icon) {
        message = msg;
        iconName = icon || "wifi";
        showing = true;
        toast.y = -toast.height;
        slideIn.start();
        autoHideTimer.restart();
    }

    function hide() {
        slideOut.start();
    }

    anchors.fill: parent
    z: 2950
    Component.onCompleted: {
        initDelayTimer.start();
    }

    Rectangle {
        id: toast

        anchors.horizontalCenter: parent.horizontalCenter
        y: -height
        width: Math.min(parent.width - 32, 300)
        height: Constants.touchTargetSmall
        radius: MRadius.sm
        color: Qt.rgba(0, 0, 0, 0.95)
        border.width: 1
        border.color: MColors.border
        visible: connectionToast.showing

        MTopHairline {
            radius: parent.radius
            color: Qt.rgba(255, 255, 255, 0.03)
            lineWidth: 1
        }

        Row {
            anchors.centerIn: parent
            spacing: Constants.spacingMedium

            Icon {
                name: connectionToast.iconName
                size: Constants.iconSizeMedium
                color: MColors.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: connectionToast.message
                color: MColors.text
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    NumberAnimation {
        id: slideIn

        target: toast
        property: "y"
        to: Constants.statusBarHeight + 16
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut

        target: toast
        property: "y"
        to: -toast.height
        duration: 200
        easing.type: Easing.InCubic
        onFinished: {
            connectionToast.showing = false;
        }
    }

    Timer {
        id: autoHideTimer

        interval: 3000
        onTriggered: hide()
    }

    Connections {
        function onIsWifiOnChanged() {
            if (connectionToast.initialized && SystemStatusStore.isWifiOn)
                show("Connected to " + (SystemStatusStore.wifiNetwork || "WiFi"), "wifi");
        }

        function onIsBluetoothOnChanged() {
            if (connectionToast.initialized && SystemStatusStore.isBluetoothOn)
                show("Bluetooth enabled", "bluetooth");
        }

        function onIsAirplaneModeChanged() {
            if (!connectionToast.initialized)
                return;

            if (SystemStatusStore.isAirplaneMode)
                show("Airplane mode enabled", "plane");
            else
                show("Airplane mode disabled", "plane");
        }

        target: SystemStatusStore
    }

    Timer {
        id: initDelayTimer

        interval: 1000
        onTriggered: {
            connectionToast.initialized = true;
        }
    }
}
