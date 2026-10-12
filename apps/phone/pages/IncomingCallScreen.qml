import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: incomingCallScreen

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

    anchors.fill: parent
    color: MColors.background
    z: 1000
    visible: false

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
                    text: incomingCallScreen.callerName.charAt(0).toUpperCase()
                    font.pixelSize: MTypography.sizeXLarge * 3
                    font.weight: Font.Bold
                    color: MColors.accent
                }

                SequentialAnimation on scale {
                    running: incomingCallScreen.visible
                    loops: Animation.Infinite

                    NumberAnimation {
                        from: 1
                        to: 1.1
                        duration: 800
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        from: 1.1
                        to: 1
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
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: incomingCallScreen.callerName
                    font.pixelSize: MTypography.sizeXLarge
                    font.weight: Font.Bold
                    color: MColors.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: incomingCallScreen.callerNumber
                    font.pixelSize: MTypography.sizeLarge
                    color: MColors.textSecondary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
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
                color: MColors.error
                border.width: Constants.borderWidthThick
                border.color: MColors.errorDim

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Decline call from %1").arg(incomingCallScreen.callerName)
                Accessible.onPressAction: {
                    TelephonyService.hangup();
                    incomingCallScreen.hide();
                }

                Icon {
                    anchors.centerIn: parent
                    name: "phone"
                    size: Constants.iconSizeLarge
                    color: MColors.textPrimary
                    rotation: 135
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        TelephonyService.hangup();
                        incomingCallScreen.hide();
                    }
                }
            }

            Rectangle {
                width: Constants.touchTargetLarge * 1.5
                height: Constants.touchTargetLarge * 1.5
                radius: width / 2
                color: MColors.success
                border.width: Constants.borderWidthThick
                border.color: MColors.successDim

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Answer call from %1").arg(incomingCallScreen.callerName)
                Accessible.onPressAction: {
                    TelephonyService.answer();
                    incomingCallScreen.hide();
                }

                Icon {
                    anchors.centerIn: parent
                    name: "phone"
                    size: Constants.iconSizeLarge
                    color: MColors.textPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        TelephonyService.answer();
                        incomingCallScreen.hide();
                    }
                }
            }
        }
    }
}
