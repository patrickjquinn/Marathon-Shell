pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// The whole screen for a call: ringing, and in progress over the lock screen.
Item {
    id: callOverlay

    property string callerNumber: ""
    property string callerName: ""
    property bool isRinging: false
    property bool answeredHere: false
    property bool pinShown: false
    // Answered while locked: the call stays here and the session stays locked.
    readonly property bool inCall: answeredHere && SessionStore.isLocked && Modem.callState !== "idle" && Modem.callState !== "terminated"
    readonly property string title: callerName || MPhoneNumber.format(callerNumber) || qsTr("Unknown caller")
    readonly property string initials: {
        const words = callerName.trim().split(/\s+/).filter(w => w.length > 0);
        return words.slice(0, 2).map(w => w[0].toUpperCase()).join("");
    }
    property real answeredAt: 0
    property int elapsed: 0
    // Sized from the screen, not the theme's DPI: the same layout on the
    // Q25's square panel as on a tall phone.
    readonly property real side: Math.min(width, height)
    readonly property real bigButton: Math.round(side * 0.2)
    readonly property real smallButton: Math.round(side * 0.13)

    signal unlockRequested

    function show(number, name) {
        callerNumber = number;
        callerName = name || "";
        answeredHere = false;
        isRinging = true;
        AudioManagerCpp.playRingtone();
        HapticManager.vibrate(1000);
        Logger.info("IncomingCallOverlay", "Showing call from: " + number);
    }

    // Ends the ringing prompt; an answered call stays on screen while locked.
    function hide() {
        isRinging = false;
        AudioManagerCpp.stopRingtone();
        Logger.info("IncomingCallOverlay", "Hiding call overlay");
    }

    function answer() {
        Logger.info("IncomingCallOverlay", "Call answered");
        HapticManager.heavy();
        answeredHere = true;
        answeredAt = Date.now();
        elapsed = 0;
        hide();
        UIStore.openApp("phone", qsTr("Phone"), "");
        // Last: the call state change can unload this overlay.
        Modem.answer();
    }

    function decline() {
        Logger.info("IncomingCallOverlay", "Call declined");
        HapticManager.medium();
        hide();
        // Last: the call state change can unload this overlay.
        Modem.hangup();
    }

    function silence() {
        AudioManagerCpp.stopRingtone();
        HapticManager.cancelVibration();
    }

    function duration(seconds) {
        const m = Math.floor(seconds / 60), s = seconds % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    anchors.fill: parent
    z: Constants.zIndexModalOverlay + 100
    visible: isRinging || (inCall && !pinShown)
    opacity: callOverlay.visible ? 1 : 0

    // A filled circle with its label beneath: the call's choices.
    component CallButton: Column {
        id: button

        property string iconName
        property string label
        property color fill: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.14)
        property bool checked: false
        property real size: callOverlay.smallButton

        signal activated

        spacing: Silica.Theme.paddingMedium
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checked: checked
        Accessible.onPressAction: activated()

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: button.size
            height: width
            radius: width / 2
            color: button.checked ? Silica.Theme.primaryColor : button.fill
            scale: tap.pressed ? 0.92 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: MMotion.micro
                    easing.type: Easing.OutCubic
                }
            }

            GlyphIcon {
                anchors.centerIn: parent
                name: button.iconName
                size: button.size * 0.42
                color: button.checked ? "black" : "white"
            }
            MouseArea {
                id: tap

                anchors.fill: parent
                anchors.margins: -Silica.Theme.paddingSmall
                onClicked: button.activated()
            }
        }
        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: button.label
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
            color: Silica.Theme.primaryColor
        }
    }

    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
        brightest: AmbienceService.brightest
        darkest: AmbienceService.darkest
    }

    // Darker towards the buttons, so they read over any wallpaper.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.rgba(0, 0, 0, 0.25)
            }
            GradientStop {
                position: 1
                color: Qt.rgba(0, 0, 0, 0.7)
            }
        }
    }

    // Swallow touches meant for whatever is underneath.
    MouseArea {
        anchors.fill: parent
    }

    Silica.Label {
        id: status

        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight + Silica.Theme.paddingLarge
        anchors.horizontalCenter: parent.horizontalCenter
        text: callOverlay.isRinging ? (Modem.operatorName ? qsTr("Incoming call · %1").arg(Modem.operatorName) : qsTr("Incoming call")) : qsTr("On call · %1").arg(callOverlay.duration(callOverlay.elapsed))
        font.pixelSize: Silica.Theme.fontSizeSmall
        font.features: ({
                "tnum": 1
            })
        color: Silica.Theme.secondaryHighlightColor
    }

    // The caller: initials (or a figure) in a circle that pulses while it rings.
    Item {
        id: caller

        readonly property real size: Math.round(callOverlay.side * (callOverlay.isRinging ? 0.24 : 0.17))

        anchors.top: status.bottom
        anchors.topMargin: Silica.Theme.paddingLarge * 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: size
        height: size

        Repeater {
            model: 2

            Rectangle {
                id: ripple

                required property int index

                anchors.centerIn: parent
                width: caller.size
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 3))
                border.color: Silica.Theme.highlightColor
                opacity: 0
                visible: callOverlay.isRinging

                SequentialAnimation {
                    running: MMotion.gate(callOverlay.isRinging && Display.screenOn)
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: ripple.index * 900
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: ripple
                            property: "scale"
                            from: 1
                            to: 1.6
                            duration: 1800
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: ripple
                            property: "opacity"
                            from: 0.45
                            to: 0
                            duration: 1800
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.18)
            border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
            border.color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.5)

            Silica.Label {
                anchors.centerIn: parent
                visible: callOverlay.initials !== ""
                text: callOverlay.initials
                font.family: Silica.Theme.fontFamilyHeading
                font.pixelSize: caller.size * 0.36
                font.weight: Font.Light
                color: Silica.Theme.highlightColor
            }
            GlyphIcon {
                anchors.centerIn: parent
                visible: callOverlay.initials === ""
                name: "user"
                size: caller.size * 0.45
                color: Silica.Theme.highlightColor
            }
        }
    }

    Column {
        anchors.top: caller.bottom
        anchors.topMargin: Silica.Theme.paddingLarge * 1.5
        x: Silica.Theme.horizontalPageMargin
        width: parent.width - 2 * Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingSmall

        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: callOverlay.title
            font.family: Silica.Theme.fontFamilyHeading
            font.pixelSize: Silica.Theme.fontSizeHuge
            font.weight: Font.Light
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Silica.Theme.fontSizeLarge
            color: Silica.Theme.primaryColor
            truncationMode: Silica.TruncationMode.Fade
        }
        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: callOverlay.callerName !== ""
            text: MPhoneNumber.format(callOverlay.callerNumber)
            font.pixelSize: Silica.Theme.fontSizeMedium
            color: Silica.Theme.secondaryColor
        }
    }

    // Ringing: decline and answer far apart, silence between them.
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingLarge * 2
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(callOverlay.width * 0.1)
        visible: callOverlay.isRinging

        CallButton {
            objectName: "declineCall"
            size: callOverlay.bigButton
            fill: "#e5483f"
            iconName: "phone-disconnect"
            label: qsTr("Decline")
            onActivated: callOverlay.decline()
        }
        CallButton {
            objectName: "silenceCall"
            anchors.verticalCenter: parent.verticalCenter
            iconName: "bell-slash"
            label: qsTr("Silence")
            onActivated: callOverlay.silence()
        }
        CallButton {
            objectName: "answerCall"
            size: callOverlay.bigButton
            fill: "#34b55a"
            iconName: "phone"
            label: qsTr("Answer")
            onActivated: callOverlay.answer()
        }
    }

    // In a call over the lock screen: mute, end and speaker; the keypad and
    // the rest behind the PIN.
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingLarge
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Silica.Theme.paddingMedium
        visible: callOverlay.inCall && !callOverlay.isRinging

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(callOverlay.width * 0.1)

            CallButton {
                objectName: "muteCall"
                anchors.verticalCenter: parent.verticalCenter
                iconName: "microphone-slash"
                label: qsTr("Mute")
                checked: Modem.callMuted
                onActivated: Modem.setCallMuted(!Modem.callMuted)
            }
            CallButton {
                objectName: "endCall"
                size: callOverlay.bigButton
                fill: "#e5483f"
                iconName: "phone-disconnect"
                label: qsTr("End call")
                onActivated: {
                    HapticManager.medium();
                    Modem.hangup();
                }
            }
            CallButton {
                objectName: "speakerCall"
                anchors.verticalCenter: parent.verticalCenter
                iconName: "speaker-high"
                label: qsTr("Speaker")
                checked: Modem.speakerphone
                onActivated: Modem.setSpeakerphone(!Modem.speakerphone)
            }
        }
        Silica.Label {
            objectName: "unlockForCall"
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Keypad and more")
            font.pixelSize: Silica.Theme.fontSizeSmall
            color: keypad.pressed ? Silica.Theme.highlightColor : Silica.Theme.secondaryHighlightColor
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.onPressAction: callOverlay.unlockRequested()

            MouseArea {
                id: keypad

                anchors.fill: parent
                anchors.margins: -Silica.Theme.paddingLarge
                onClicked: callOverlay.unlockRequested()
            }
        }
    }

    // The call's length, ticking only while it is on a lit screen.
    Timer {
        interval: 1000
        repeat: true
        running: callOverlay.inCall && callOverlay.visible && Display.screenOn
        triggeredOnStart: true
        onTriggered: callOverlay.elapsed = Math.floor((Date.now() - callOverlay.answeredAt) / 1000)
    }

    transform: Translate {
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
            easing.type: Easing.OutCubic
        }
    }
}
