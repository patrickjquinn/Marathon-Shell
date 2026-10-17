pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: callOverlay

    property string callerNumber: ""
    property string callerName: ""
    property bool isRinging: false
    property bool answeredHere: false
    property bool pinShown: false
    // Answered while locked: the call stays here and the session stays locked.
    readonly property bool inCall: answeredHere && SessionStore.isLocked && TelephonyService.callState !== "idle" && TelephonyService.callState !== "terminated"

    signal unlockRequested

    function show(number, name) {
        callerNumber = number;
        callerName = name || "";
        answeredHere = false;
        isRinging = true;
        AudioPolicyControllerCpp.playRingtone();
        HapticManager.vibrate(1000);
        Logger.info("IncomingCallOverlay", "Showing call from: " + number);
    }

    // Ends the ringing prompt; an answered call stays on screen while locked.
    function hide() {
        isRinging = false;
        AudioPolicyControllerCpp.stopRingtone();
        Logger.info("IncomingCallOverlay", "Hiding call overlay");
    }

    function silence() {
        AudioPolicyControllerCpp.stopRingtone();
        HapticManager.stopVibration();
    }

    anchors.fill: parent
    z: Constants.zIndexModalOverlay + 100
    visible: isRinging || (inCall && !pinShown)
    opacity: callOverlay.visible ? 1 : 0

    // A ring with its label beneath, as the power menu's choices.
    component CallAction: Column {
        id: action

        property string iconName
        property string label
        property bool emphasised: false

        signal activated

        spacing: Silica.Theme.paddingMedium

        MCircularIconButton {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Silica.Theme.itemSizeExtraLarge
            height: width
            iconName: action.iconName
            iconSize: Silica.Theme.iconSizeMedium
            variant: action.emphasised ? "primary" : "secondary"
            a11yName: action.label
            onClicked: action.activated()
        }

        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: action.label
            font.pixelSize: Silica.Theme.fontSizeSmall
            color: action.emphasised ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }
    }

    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    // Swallow touches meant for whatever is underneath.
    MouseArea {
        anchors.fill: parent
    }

    Column {
        anchors.centerIn: parent
        spacing: Silica.Theme.paddingLarge * 3
        width: parent.width - 2 * Silica.Theme.horizontalPageMargin

        Column {
            width: parent.width
            spacing: Silica.Theme.paddingLarge

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Silica.Theme.itemSizeHuge
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

                GlyphIcon {
                    anchors.centerIn: parent
                    name: "user"
                    size: Silica.Theme.iconSizeLarge
                    color: Silica.Theme.primaryColor
                }
            }

            Column {
                width: parent.width
                spacing: Silica.Theme.paddingSmall

                Silica.Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: callOverlay.isRinging ? qsTr("Incoming call") : qsTr("Call in progress")
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    color: Silica.Theme.secondaryHighlightColor
                }

                Silica.Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: callOverlay.callerName || MPhoneNumber.format(callOverlay.callerNumber) || "Unknown caller"
                    font.family: Silica.Theme.fontFamilyHeading
                    font.pixelSize: Silica.Theme.fontSizeExtraLarge
                    font.weight: Font.Light
                    color: Silica.Theme.highlightColor
                    truncationMode: Silica.TruncationMode.Fade
                }

                Silica.Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: MPhoneNumber.format(callOverlay.callerNumber)
                    visible: callOverlay.callerName !== ""
                    font.pixelSize: Silica.Theme.fontSizeMedium
                    color: Silica.Theme.secondaryColor
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Silica.Theme.itemSizeLarge
            visible: callOverlay.isRinging

            CallAction {
                objectName: "declineCall"
                iconName: "phone-disconnect"
                label: qsTr("Decline")
                onActivated: {
                    Logger.info("IncomingCallOverlay", "Call declined");
                    HapticManager.medium();
                    callOverlay.hide();
                    // Last: the call state change can unload this overlay.
                    TelephonyService.hangup();
                }
            }

            CallAction {
                objectName: "answerCall"
                iconName: "phone"
                label: qsTr("Answer")
                emphasised: true
                onActivated: {
                    Logger.info("IncomingCallOverlay", "Call answered");
                    HapticManager.heavy();
                    callOverlay.answeredHere = true;
                    callOverlay.hide();
                    UIStore.openApp("phone", "Phone", "");
                    // Last: the call state change can unload this overlay.
                    TelephonyService.answer();
                }
            }
        }

        CallAction {
            objectName: "endCall"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: callOverlay.inCall && !callOverlay.isRinging
            iconName: "phone-disconnect"
            label: qsTr("End call")
            onActivated: {
                HapticManager.medium();
                TelephonyService.hangup();
            }
        }

        Silica.Button {
            objectName: "unlockForCall"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: callOverlay.inCall && !callOverlay.isRinging
            text: qsTr("Unlock for call options")
            onClicked: callOverlay.unlockRequested()
        }
    }

    transform: Translate {
        id: slideTransform

        y: callOverlay.visible ? 0 : -callOverlay.height

        Behavior on y {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.fast
        }
    }
}
