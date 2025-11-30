import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Item {
    id: connectionToast
    anchors.fill: parent
    z: 2950

    property string message: ""
    property string iconName: "wifi"
    property bool showing: false

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
        visible: showing

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.03)
        }

        Row {
            anchors.centerIn: parent
            spacing: Constants.spacingMedium

            Icon {
                name: iconName
                size: Constants.iconSizeMedium
                color: MColors.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: message
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
            showing = false;
        }
    }

    Timer {
        id: autoHideTimer
        interval: 3000
        onTriggered: hide()
    }

    property bool initialized: false

    Connections {
        target: SystemStatusStore
        function onIsWifiOnChanged() {
            if (initialized && SystemStatusStore.isWifiOn) {
                show("Connected to " + (SystemStatusStore.wifiNetwork || "WiFi"), "wifi");
            }
        }
        function onIsBluetoothOnChanged() {
            if (initialized && SystemStatusStore.isBluetoothOn) {
                show("Bluetooth enabled", "bluetooth");
            }
        }
        function onIsAirplaneModeChanged() {
            if (!initialized)
                return;
            if (SystemStatusStore.isAirplaneMode) {
                show("Airplane mode enabled", "plane");
            } else {
                show("Airplane mode disabled", "plane");
            }
        }
    }

    Component.onCompleted: {
        initDelayTimer.start();
    }

    Timer {
        id: initDelayTimer
        interval: 1000
        onTriggered: {
            connectionToast.initialized = true;
        }
    }
}
