import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

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
        width: Math.min(toastRow.width + Silica.Theme.paddingLarge * 2, parent.width - Silica.Theme.paddingSmall * 2)
        height: Silica.Theme.itemSizeSmall
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        visible: connectionToast.showing

        Row {
            id: toastRow

            anchors.centerIn: parent
            spacing: Silica.Theme.paddingMedium

            GlyphIcon {
                name: connectionToast.iconName
                size: Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Silica.Label {
                text: connectionToast.message
                color: Silica.Theme.primaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    NumberAnimation {
        id: slideIn

        target: toast
        property: "y"
        to: Constants.statusBarHeight + Silica.Theme.paddingSmall
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
        onTriggered: connectionToast.hide()
    }

    Connections {
        function onIsWifiOnChanged() {
            if (connectionToast.initialized && SystemStatusStore.isWifiOn)
                connectionToast.show("Connected to " + (SystemStatusStore.wifiNetwork || "WiFi"), "wifi");
        }

        function onIsBluetoothOnChanged() {
            if (connectionToast.initialized && SystemStatusStore.isBluetoothOn)
                connectionToast.show("Bluetooth enabled", "bluetooth");
        }

        function onIsAirplaneModeChanged() {
            if (!connectionToast.initialized)
                return;

            if (SystemStatusStore.isAirplaneMode)
                connectionToast.show("Airplane mode enabled", "plane");
            else
                connectionToast.show("Airplane mode disabled", "plane");
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
