import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: incomingCallScreen
    anchors.fill: parent
    color: MColors.background
    z: 1000
    visible: false

    property string callerNumber: ""
    property string callerName: "Unknown"

    function show(number, name) {
        callerNumber = number;
        callerName = name || "Unknown";
        visible = true;
    }

    function hide() {
        visible = false;
    }

    Column {
        anchors.centerIn: parent
        spacing: MSpacing.xl * 2
        width: parent.width * 0.8

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: MSpacing.lg

            Rectangle {
                width: Constants.iconSizeXLarge * 3
                height: Constants.iconSizeXLarge * 3
                radius: width / 2
                color: MColors.surface
                border.width: Constants.borderWidthThick
                border.color: MColors.accent
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    anchors.centerIn: parent
                    text: callerName.charAt(0).toUpperCase()
                    font.pixelSize: MTypography.sizeXLarge * 3
                    font.weight: Font.Bold
                    color: MColors.accent
                }

                SequentialAnimation on scale {
                    running: incomingCallScreen.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 1.0
                        to: 1.1
                        duration: 800
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        from: 1.1
                        to: 1.0
                        duration: 800
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: MSpacing.sm

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Incoming Call"
                    font.pixelSize: MTypography.sizeSmall
                    font.weight: Font.Medium
                    color: MColors.textSecondary
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: callerName
                    font.pixelSize: MTypography.sizeXLarge
                    font.weight: Font.Bold
                    color: MColors.text
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: callerNumber
                    font.pixelSize: MTypography.sizeLarge
                    color: MColors.textSecondary
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: MSpacing.xl * 2

            Rectangle {
                width: Constants.touchTargetLarge * 1.5
                height: Constants.touchTargetLarge * 1.5
                radius: width / 2
                color: "#E74C3C"
                border.width: Constants.borderWidthThick
                border.color: "#C0392B"

                Icon {
                    anchors.centerIn: parent
                    name: "phone"
                    size: Constants.iconSizeLarge
                    color: "white"
                    rotation: 135
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (typeof TelephonyService !== 'undefined') {
                            TelephonyService.hangup();
                        }
                        hide();
                    }
                }
            }

            Rectangle {
                width: Constants.touchTargetLarge * 1.5
                height: Constants.touchTargetLarge * 1.5
                radius: width / 2
                color: "#27AE60"
                border.width: Constants.borderWidthThick
                border.color: "#229954"

                Icon {
                    anchors.centerIn: parent
                    name: "phone"
                    size: Constants.iconSizeLarge
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (typeof TelephonyService !== 'undefined') {
                            TelephonyService.answer();
                        }
                        hide();
                    }
                }
            }
        }
    }
}
