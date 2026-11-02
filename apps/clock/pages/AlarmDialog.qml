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
            // On a square or landscape screen Repeat sits beside the dial, not below the fold.
            Grid {
                id: body

                readonly property bool sideBySide: root.width > root.height

                width: parent.width
                columns: sideBySide ? 2 : 1
                leftPadding: sideBySide ? Theme.horizontalPageMargin : 0
                rowSpacing: Theme.paddingLarge
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                TimePicker {
                    id: picker

                    objectName: "timePicker"

                    Label {
                        anchors.centerIn: parent
                        text: picker.timeText
                        font.pixelSize: Theme.fontSizeExtraLarge
                        color: Theme.highlightColor
                    }
                }
                Column {
                    width: body.width - (body.sideBySide ? body.leftPadding + picker.width : 0)
                    spacing: Theme.paddingLarge

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
            }
        }

        VerticalScrollDecorator {}
    }
}
