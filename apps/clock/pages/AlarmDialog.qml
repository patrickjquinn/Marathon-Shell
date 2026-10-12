import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

Dialog {
    id: root

    property var app
    property string alarmId: ""
    property alias hour: picker.hour
    property alias minute: picker.minute
    property alias label: labelField.text
    property alias repeat: weekdays.days

    onAccepted: app.saveAlarm(alarmId, hour, minute, label.trim(), repeat)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Save")
                title: root.alarmId ? qsTr("Edit alarm") : qsTr("New alarm")
            }
            TimePicker {
                id: picker

                objectName: "timePicker"
                anchors.horizontalCenter: parent.horizontalCenter

                Label {
                    anchors.centerIn: parent
                    text: picker.timeText
                    font.pixelSize: Theme.fontSizeExtraLarge
                    color: Theme.highlightColor
                }
            }
            SectionHeader {
                text: qsTr("Repeat")
            }
            WeekdaySelector {
                id: weekdays
            }
            TextField {
                id: labelField

                objectName: "labelField"
                width: parent.width
                label: qsTr("Alarm name")
                placeholderText: qsTr("Alarm")
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        VerticalScrollDecorator {}
    }
}
