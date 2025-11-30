import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: alarmOverlay
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.95)
    visible: false
    z: 10000

    property var currentAlarm: null

    function show(alarm) {
        currentAlarm = alarm;
        visible = true;

        swipeUpText.opacity = 1.0;
        swipeAnimation.start();
    }

    function dismiss() {
        if (currentAlarm) {
            AlarmManager.dismissAlarm(currentAlarm.id);
            currentAlarm = null;
        }
        visible = false;
    }

    function snooze() {
        if (currentAlarm) {
            AlarmManager.snoozeAlarm(currentAlarm.id);
            currentAlarm = null;
        }
        visible = false;
    }

    MouseArea {
        anchors.fill: parent
        preventStealing: true

        property real startY: 0
        property bool dragging: false

        onPressed: mouse => {
            startY = mouse.y;
            dragging = false;
        }

        onPositionChanged: mouse => {
            if (Math.abs(mouse.y - startY) > 20) {
                dragging = true;
            }

            if (dragging) {
                var delta = mouse.y - startY;

                if (delta < -100) {
                    alarmOverlay.dismiss();
                }
            }
        }

        onReleased: {
            dragging = false;
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: Constants.spacingLarge * 2

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "bell"
            size: Constants.iconSizeXLarge * 2
            color: MColors.accentBright
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: currentAlarm ? currentAlarm.label : "Alarm"
            color: MColors.text
            font.pixelSize: MTypography.sizeXLarge
            font.weight: MTypography.weightBold
            font.family: MTypography.fontFamily
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(new Date(), "hh:mm")
            color: MColors.textSecondary
            font.pixelSize: MTypography.sizeXXLarge
            font.weight: MTypography.weightMedium
            font.family: MTypography.fontFamily
        }

        Item {
            height: Constants.spacingLarge
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingLarge

            Rectangle {
                width: Constants.touchTargetXLarge
                height: Constants.touchTargetLarge
                radius: MRadius.lg
                color: MColors.surface

                Column {
                    anchors.centerIn: parent
                    spacing: Constants.spacingSmall

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "clock"
                        size: Constants.iconSizeMedium
                        color: MColors.text
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Snooze"
                        color: MColors.text
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium();
                        alarmOverlay.snooze();
                    }
                }
            }

            Rectangle {
                width: Constants.touchTargetXLarge
                height: Constants.touchTargetLarge
                radius: MRadius.lg
                color: MColors.accent

                Column {
                    anchors.centerIn: parent
                    spacing: Constants.spacingSmall

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "x"
                        size: Constants.iconSizeMedium
                        color: MColors.background
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Dismiss"
                        color: MColors.background
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium();
                        alarmOverlay.dismiss();
                    }
                }
            }
        }

        Item {
            height: Constants.spacingLarge
        }

        Text {
            id: swipeUpText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "↑ Swipe up to dismiss"
            color: MColors.textSecondary
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily

            SequentialAnimation {
                id: swipeAnimation
                loops: Animation.Infinite

                NumberAnimation {
                    target: swipeUpText
                    property: "opacity"
                    from: 1.0
                    to: 0.3
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: swipeUpText
                    property: "opacity"
                    from: 0.3
                    to: 1.0
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    Timer {
        id: updateTimeTimer
        interval: 1000
        repeat: true
        running: alarmOverlay.visible
        onTriggered: {
            alarmOverlay.currentAlarmChanged();
        }
    }

    Connections {
        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null

        function onAlarmTriggered(alarm) {
            alarmOverlay.show(alarm);
        }
    }
}
