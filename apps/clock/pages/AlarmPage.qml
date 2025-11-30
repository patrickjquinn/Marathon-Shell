import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import "../components"

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

                delegate: AlarmItem {
                    width: alarmsList.width
                    alarmId: modelData.id
                    alarmHour: modelData.time ? _getHour(modelData.time) : (modelData.hour || 0)
                    alarmMinute: modelData.time ? _getMinute(modelData.time) : (modelData.minute || 0)
                    alarmLabel: modelData.label
                    alarmEnabled: modelData.enabled

                    onClicked: {
                        alarmEditorDialog.openForEdit(alarmId, alarmHour, alarmMinute, alarmLabel);
                    }

                    onToggled: {
                        clockApp.toggleAlarm(alarmId);
                    }

                    onDeleted: {
                        clockApp.deleteAlarm(alarmId);
                    }

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
                }

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
