import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Lock-screen network agent. GNOME 50.1 added a captive-portal /
// WiFi-credential prompt that surfaces on the lock screen before the
// user authenticates, matching iOS / Android behaviour: the device can
// associate with a known SSID, the user can enter a password for a new
// SSID, and a captive-portal hotspot landing page can be acknowledged
// without unlocking.
//
// Marathon's pattern: a low-elevation MGlass card slides up from the
// lock-screen shortcuts. The PIN keypad is hidden while this is open
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

    // Backdrop dim — taps outside dismiss.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.45
        MouseArea {
            anchors.fill: parent
            onClicked: agent.hide()
        }
    }

    // Card slides up from bottom.
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - Constants.safeAreaBottom - MSpacing.xl
        width: parent.width - Constants.safeAreaLeft - Constants.safeAreaRight - MSpacing.xl * 2
        height: cardCol.implicitHeight + MSpacing.xl * 2
        radius: MRadius.lg
        color: MColors.elev1
        border.color: MColors.borderSubtle
        border.width: 1

        Column {
            id: cardCol
            anchors.centerIn: parent
            width: parent.width - MSpacing.xl * 2
            spacing: MSpacing.md

            Row {
                width: parent.width
                spacing: MSpacing.md

                Icon {
                    name: "wifi"
                    size: Math.round(28 * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: agent.targetSsid !== "" ? "Sign in to " + agent.targetSsid : "Sign in to WiFi"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.weight: MTypography.weightDemiBold
                        font.family: MTypography.fontFamily
                        elide: Text.ElideRight
                        width: card.width - MSpacing.xl * 2 - Math.round(28 * Constants.scaleFactor) - MSpacing.md
                    }
                    Text {
                        text: agent.targetSecurity
                        color: MColors.textTertiary
                        font.pixelSize: MTypography.sizeFootnote
                        font.family: MTypography.fontFamily
                    }
                }
            }

            // Password input. Uses native TextInput; the virtual keyboard
            // is the system one, so it pops up under our z-layer
            // automatically when this field gains focus.
            Rectangle {
                width: parent.width
                height: Math.round(44 * Constants.scaleFactor)
                radius: MRadius.md
                color: MColors.elev2
                border.color: passwordField.activeFocus ? MColors.marathonTealBright : MColors.borderSubtle
                border.width: 1

                TextInput {
                    id: passwordField
                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.md
                    anchors.rightMargin: MSpacing.md
                    verticalAlignment: TextInput.AlignVCenter
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    echoMode: TextInput.Password
                    selectByMouse: true
                    onAccepted: agent.submit()
                }
            }

            Text {
                visible: agent.statusText !== ""
                text: agent.statusText
                color: MColors.error
                font.pixelSize: MTypography.sizeFootnote
                font.family: MTypography.fontFamily
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Row {
                width: parent.width
                spacing: MSpacing.md
                layoutDirection: Qt.RightToLeft

                // Right-aligned primary action.
                Rectangle {
                    width: (parent.width - MSpacing.md) / 2
                    height: Math.round(44 * Constants.scaleFactor)
                    radius: MRadius.md
                    color: passwordField.text.length > 0 ? MColors.marathonTealBright : MColors.elev2
                    opacity: connectArea.pressed ? 0.85 : 1.0
                    enabled: passwordField.text.length > 0

                    Text {
                        anchors.centerIn: parent
                        text: "Connect"
                        color: passwordField.text.length > 0 ? "#000000" : MColors.textTertiary
                        font.pixelSize: MTypography.sizeBody
                        font.weight: MTypography.weightDemiBold
                        font.family: MTypography.fontFamily
                    }

                    MouseArea {
                        id: connectArea
                        anchors.fill: parent
                        enabled: passwordField.text.length > 0
                        onClicked: agent.submit()
                    }
                }

                // Cancel.
                Rectangle {
                    width: (parent.width - MSpacing.md) / 2
                    height: Math.round(44 * Constants.scaleFactor)
                    radius: MRadius.md
                    color: MColors.elev2
                    border.color: MColors.borderSubtle
                    border.width: 1
                    opacity: cancelArea.pressed ? 0.85 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                    }

                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        onClicked: agent.hide()
                    }
                }
            }
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
