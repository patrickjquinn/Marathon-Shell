import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

/**
 * Lock Screen Incoming Call Overlay
 *
 * Displays over lock screen and all other content when a call comes in.
 * Provides answer/decline buttons and shows caller information.
 */
Rectangle {
    id: callOverlay
    anchors.fill: parent
    color: MColors.background
    z: Constants.zIndexModalOverlay + 100  // Above everything
    visible: false

    property string callerNumber: ""
    property string callerName: "Unknown"
    property bool isRinging: false

    signal answered
    signal declined

    function show(number, name) {
        callerNumber = number;
        callerName = name || "Unknown";
        isRinging = true;
        visible = true;

        // Play ringtone
        if (typeof AudioManager !== 'undefined') {
            AudioManager.playRingtone();
        }

        // Vibrate
        if (typeof HapticService !== 'undefined') {
            HapticService.vibrate(1000);  // 1 second pulse
        }

        Logger.info("IncomingCallOverlay", "Showing call from: " + number);
    }

    function hide() {
        isRinging = false;
        visible = false;

        // Stop ringtone
        if (typeof AudioManager !== 'undefined') {
            AudioManager.stopRingtone();
        }

        Logger.info("IncomingCallOverlay", "Hiding call overlay");
    }

    // Background with blur effect
    Rectangle {
        anchors.fill: parent
        color: MColors.background
        opacity: 0.98
    }

    Column {
        anchors.centerIn: parent
        spacing: Constants.spacingXLarge * 3
        width: parent.width * 0.85

        // Caller info section
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingXLarge

            // Avatar/Icon with pulsing animation
            Rectangle {
                width: Math.round(Constants.iconSizeXLarge * 3)
                height: Math.round(Constants.iconSizeXLarge * 3)
                radius: width / 2
                color: Qt.rgba(MColors.accent.r, MColors.accent.g, MColors.accent.b, 0.15)
                border.width: Constants.borderWidthThick
                border.color: MColors.accent
                anchors.horizontalCenter: parent.horizontalCenter

                Icon {
                    anchors.centerIn: parent
                    name: "user"
                    size: Constants.iconSizeXLarge * 1.5
                    color: MColors.accent
                }

                // Pulsing animation
                SequentialAnimation on scale {
                    running: callOverlay.isRinging
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 1.0
                        to: 1.15
                        duration: 1000
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        from: 1.15
                        to: 1.0
                        duration: 1000
                        easing.type: Easing.InOutQuad
                    }
                }

                // Ripple effect
                Repeater {
                    model: 3
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: MColors.accent
                        opacity: 0

                        SequentialAnimation on scale {
                            running: callOverlay.isRinging
                            loops: Animation.Infinite
                            PauseAnimation {
                                duration: index * 700
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    from: 1.0
                                    to: 1.8
                                    duration: 2100
                                    easing.type: Easing.OutQuad
                                }
                                NumberAnimation {
                                    target: parent
                                    property: "opacity"
                                    from: 0.6
                                    to: 0.0
                                    duration: 2100
                                }
                            }
                        }
                    }
                }
            }

            // Caller details
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingSmall

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Incoming Call"
                    font.pixelSize: MTypography.sizeSmall
                    font.weight: Font.Medium
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    opacity: 0.7
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: callerName
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: callerNumber
                    font.pixelSize: MTypography.sizeLarge
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                }
            }
        }

        // Action buttons
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingXLarge * 3

            // Decline button
            Column {
                spacing: Constants.spacingMedium

                Rectangle {
                    width: Constants.touchTargetLarge * 1.8
                    height: Constants.touchTargetLarge * 1.8
                    radius: width / 2
                    color: MColors.error
                    border.width: Constants.borderWidthThick
                    border.color: Qt.darker(MColors.error, 1.2)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Icon {
                        anchors.centerIn: parent
                        name: "phone"
                        size: Constants.iconSizeLarge
                        color: MColors.background
                        rotation: 135
                    }

                    MouseArea {
                        id: declineMouseArea
                        anchors.fill: parent
                        anchors.margins: -Constants.spacingMedium
                        onClicked: {
                            Logger.info("IncomingCallOverlay", "Call declined");
                            HapticService.medium();

                            if (typeof TelephonyService !== 'undefined') {
                                TelephonyService.hangup();
                            }

                            declined();
                            hide();
                        }
                    }

                    scale: declineMouseArea.pressed ? 0.95 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: Constants.animationDurationFast
                        }
                    }
                }

                Text {
                    text: "Decline"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.Medium
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            // Answer button
            Column {
                spacing: Constants.spacingMedium

                Rectangle {
                    width: Constants.touchTargetLarge * 1.8
                    height: Constants.touchTargetLarge * 1.8
                    radius: width / 2
                    color: MColors.success
                    border.width: Constants.borderWidthThick
                    border.color: Qt.darker(MColors.success, 1.2)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Icon {
                        anchors.centerIn: parent
                        name: "phone"
                        size: Constants.iconSizeLarge
                        color: MColors.background
                    }

                    MouseArea {
                        id: answerMouseArea
                        anchors.fill: parent
                        anchors.margins: -Constants.spacingMedium
                        onClicked: {
                            Logger.info("IncomingCallOverlay", "Call answered");
                            HapticService.heavy();

                            if (typeof TelephonyService !== 'undefined') {
                                TelephonyService.answer();
                            }

                            answered();
                            hide();

                            if (typeof UIStore !== 'undefined') {
                                UIStore.openApp("phone", "Phone", "");
                            }
                        }
                    }

                    scale: answerMouseArea.pressed ? 0.95 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: Constants.animationDurationFast
                        }
                    }
                }

                Text {
                    text: "Answer"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.Medium
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // Additional actions (swipe down hint on lock screen)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: SessionStore.isLocked ? "Answering will unlock your device" : ""
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            color: MColors.textTertiary
            opacity: 0.6
            visible: SessionStore.isLocked
        }
    }

    // Slide in animation
    transform: Translate {
        id: slideTransform
        y: callOverlay.visible ? 0 : -callOverlay.height
        Behavior on y {
            NumberAnimation {
                duration: Constants.animationDurationNormal
                easing.type: Easing.OutCubic
            }
        }
    }

    opacity: callOverlay.visible ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation {
            duration: Constants.animationDurationFast
        }
    }
}
