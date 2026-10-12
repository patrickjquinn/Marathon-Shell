import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Lock-screen network agent. GNOME 50.1 added a captive-portal /
// WiFi-credential prompt that surfaces on the lock screen before the
// user authenticates, matching iOS / Android behaviour: the device can
// associate with a known SSID, the user can enter a password for a new
// SSID, and a captive-portal hotspot landing page can be acknowledged
// without unlocking.
//
// Marathon's pattern: a full-screen Silica dialog on the ambience over
// the lock screen. The PIN keypad is hidden while this is open
// (the back arrow returns to the swipe-up affordance). After success
// the dialog dismisses and the lock screen returns to its idle state —
// the device does NOT unlock.
//
// Surfaces above lockScreen (z=1000) but BELOW the cell-broadcast
// emergency overlay (z=2000+200). An active 911 voice call and a
// Presidential WEA still preempt this prompt.
//
// Hooks: trigger via `agent.show(ssid, security)` from wherever you
// detect a missing-credential / captive-portal state. Until r201 wires
// NetworkManagerCpp's secret-needed signal to this, the agent only
// surfaces when explicitly called — keeps the lock screen quiet in
// the common case.
Item {
    id: agent

    property bool active: false
    property string targetSsid: ""
    property string targetSecurity: "WPA2"
    property string statusText: ""

    function show(ssid, security) {
        targetSsid = ssid || "";
        targetSecurity = security || "WPA2";
        statusText = "";
        passwordField.text = "";
        active = true;
    }
    function hide() {
        active = false;
        passwordField.text = "";
        statusText = "";
    }

    anchors.fill: parent
    visible: active
    z: Constants.zIndexLockScreen + 50

    // A full-screen Silica dialog on the ambience: Cancel and Connect in the
    // header corners. A tap on empty space dismisses.
    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    MouseArea {
        anchors.fill: parent
        onClicked: agent.hide()
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.safeAreaTop
        height: Silica.Theme.itemSizeLarge

        Silica.BackgroundItem {
            anchors.left: parent.left
            width: parent.width / 2
            height: parent.height
            onClicked: agent.hide()

            Silica.Label {
                anchors.left: parent.left
                anchors.leftMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: parent.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            }
        }

        Silica.BackgroundItem {
            id: connectButton

            anchors.right: parent.right
            width: parent.width / 2
            height: parent.height
            enabled: passwordField.text.length > 0
            onClicked: agent.submit()

            Silica.Label {
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: "Connect"
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: Silica.Theme.highlightColor
                opacity: connectButton.enabled ? 1 : Silica.Theme.opacityLow
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium

        GlyphIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "wifi"
            size: Silica.Theme.iconSizeLarge
            color: Silica.Theme.primaryColor
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            horizontalAlignment: Text.AlignHCenter
            text: agent.targetSsid !== "" ? "Sign in to " + agent.targetSsid : "Sign in to WiFi"
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
            truncationMode: Silica.TruncationMode.Fade
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            horizontalAlignment: Text.AlignHCenter
            text: agent.targetSecurity
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }

        Item {
            width: parent.width
            height: Silica.Theme.paddingLarge
        }

        Silica.PasswordField {
            id: passwordField

            width: parent.width
            label: "Password"
            placeholderText: "Password"
            errorHighlight: agent.statusText !== ""
            Keys.onReturnPressed: agent.submit()
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: agent.statusText !== ""
            text: agent.statusText
            wrapMode: Text.Wrap
            color: Silica.Theme.errorColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }
    }

    function submit() {
        if (passwordField.text.length === 0)
            return;
        statusText = "";
        NetworkManagerCpp.connectToNetwork(targetSsid, passwordField.text);
    }

    Connections {
        function onConnectionSuccess() {
            if (agent.active)
                agent.hide();
        }
        function onConnectionFailed(message) {
            if (agent.active)
                agent.statusText = message !== "" ? message : "Connection failed";
        }
        target: NetworkManagerCpp
    }

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.sm
            easing.type: Easing.OutCubic
        }
    }
}
