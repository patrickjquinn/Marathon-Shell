import MarathonApp.Clock
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: alarmPage

    Column {
        anchors.fill: parent
        spacing: 0

        Item {
            width: parent.width
            height: parent.height

            ListView {
                id: alarmsList

                anchors.fill: parent
                anchors.topMargin: MSpacing.md
                clip: true
                model: clockApp.alarms
                spacing: 0

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.8, Constants.screenWidth * 0.6)
                    height: emptyColumn.height
                    color: "transparent"
                    visible: alarmsList.count === 0

                    Column {
                        id: emptyColumn

                        anchors.centerIn: parent
                        spacing: MSpacing.lg

                        ClockIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "clock"
                            size: Constants.iconSizeXLarge * 2
                            color: MColors.textSecondary
                            opacity: 0.5
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No alarms set"
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: Font.Medium
                        }

                        Text {
                            width: parent.width
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Tap the + button to create an alarm"
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeBody
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                delegate: AlarmItem {
                    function _getHour(timeStr) {
                        if (!timeStr)
                            return 0;

                        var parts = timeStr.split(":");
                        return parseInt(parts[0]);
                    }

                    function _getMinute(timeStr) {
                        if (!timeStr)
                            return 0;

                        var parts = timeStr.split(":");
                        return parseInt(parts[1]);
                    }

                    width: alarmsList.width
                    alarmId: modelData && modelData.id !== undefined ? modelData.id : ""
                    alarmHour: modelData && modelData.time ? _getHour(modelData.time) : (modelData && modelData.hour !== undefined ? modelData.hour : 0)
                    alarmMinute: modelData && modelData.time ? _getMinute(modelData.time) : (modelData && modelData.minute !== undefined ? modelData.minute : 0)
                    alarmLabel: modelData && modelData.label !== undefined ? modelData.label : "Alarm"
                    alarmEnabled: modelData && modelData.enabled !== undefined ? modelData.enabled : false
                    onClicked: {
                        alarmEditorDialog.openForEdit(alarmId, alarmHour, alarmMinute, alarmLabel);
                    }
                    onToggled: {
                        clockApp.toggleAlarm(alarmId);
                    }
                    onDeleted: {
                        clockApp.deleteAlarm(alarmId);
                    }
                }
            }
        }
    }

    MIconButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        iconName: "plus"
        iconSize: 28
        variant: "primary"
        shape: "circular"
        onClicked: {
            alarmEditorDialog.open();
        }
    }

    AlarmEditorDialog {
        id: alarmEditorDialog

        onAlarmCreated: function (hour, minute) {
            clockApp.createAlarm(hour, minute, "Alarm", true);
        }
        onAlarmUpdated: function (alarmId, hour, minute) {
            clockApp.updateAlarm(alarmId, hour, minute, "Alarm", true, []);
        }
    }
}
