pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../CalendarLogic.js" as Logic

Dialog {
    id: dialog

    property var app
    // The event being edited; null for a new one.
    property var original: null
    property alias title: titleField.text
    property date date: new Date()
    property int hour: 12
    property int minute: 0
    property alias allDay: allDaySwitch.checked
    property string recurring: "none"
    property int reminder: 0
    property alias description: descriptionArea.text

    function event() {
        return Object.assign({}, original || {}, {
            title: title.trim(),
            date: Logic.dateKey(date),
            time: Logic.timeString(hour, minute),
            allDay: allDay,
            recurring: recurring,
            reminder: reminder,
            description: description.trim()
        });
    }

    canAccept: title.trim() !== ""
    onAccepted: app.saveEvent(event())

    Component {
        id: datePickerComponent

        DatePickerDialog {}
    }
    Component {
        id: timePickerComponent

        TimePickerDialog {}
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.original ? qsTr("Edit event") : qsTr("New event")
            }
            TextField {
                id: titleField

                objectName: "titleField"
                width: parent.width
                label: qsTr("Title")
                placeholderText: qsTr("Event title")
                focus: dialog.original === null
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: descriptionArea.focus = true
            }
            ValueButton {
                objectName: "dateButton"
                label: qsTr("Date")
                value: Format.formatDate(dialog.date, Formatter.DateLong)
                onClicked: {
                    const picker = pageStack.push(datePickerComponent, { date: dialog.date });
                    picker.accepted.connect(function () {
                        dialog.date = picker.date;
                    });
                }
            }
            TextSwitch {
                id: allDaySwitch

                objectName: "allDaySwitch"
                text: qsTr("All day")
            }
            ValueButton {
                objectName: "timeButton"
                label: qsTr("Time")
                visible: !dialog.allDay
                value: Format.formatDate(new Date(2000, 0, 1, dialog.hour, dialog.minute), Formatter.TimeValue)
                onClicked: {
                    const picker = pageStack.push(timePickerComponent, { hour: dialog.hour, minute: dialog.minute });
                    picker.accepted.connect(function () {
                        dialog.hour = picker.hour;
                        dialog.minute = picker.minute;
                    });
                }
            }
            ComboBox {
                objectName: "repeatBox"
                label: qsTr("Repeat")
                currentIndex: Math.max(0, Logic.repeatModes.indexOf(dialog.recurring))
                onCurrentIndexChanged: dialog.recurring = Logic.repeatModes[currentIndex]
                menu: ContextMenu {
                    Repeater {
                        model: Logic.repeatModes

                        MenuItem {
                            required property string modelData

                            text: dialog.app.repeatText(modelData)
                        }
                    }
                }
            }
            ComboBox {
                objectName: "reminderBox"
                label: qsTr("Reminder")
                currentIndex: Math.max(0, Logic.reminderMinutes.indexOf(dialog.reminder))
                onCurrentIndexChanged: dialog.reminder = Logic.reminderMinutes[currentIndex]
                menu: ContextMenu {
                    Repeater {
                        model: Logic.reminderMinutes

                        MenuItem {
                            required property int modelData

                            text: dialog.app.reminderText(modelData)
                        }
                    }
                }
            }
            TextArea {
                id: descriptionArea

                objectName: "descriptionArea"
                width: parent.width
                label: qsTr("Description")
                placeholderText: qsTr("Description")
            }
        }

        VerticalScrollDecorator {}
    }
}
