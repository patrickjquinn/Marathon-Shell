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
    // Minutes; the end moves with the start.
    property int duration: 60
    readonly property string endTime: Logic.addMinutes(Logic.timeString(hour, minute), duration)
    readonly property int endHour: Logic.parseTime(endTime).hour
    readonly property int endMinute: Logic.parseTime(endTime).minute
    property alias location: locationField.text
    property alias allDay: allDaySwitch.checked
    property string recurring: "none"
    property int reminder: 0
    property alias description: descriptionArea.text
    property bool showErrors: false

    function setEnd(h, m) {
        duration = Logic.duration(Logic.timeString(hour, minute), Logic.timeString(h, m));
    }

    function event() {
        return Object.assign({}, original || {}, {
            title: title.trim(),
            date: Logic.dateKey(date),
            time: Logic.timeString(hour, minute),
            endTime: endTime,
            location: location.trim(),
            allDay: allDay,
            recurring: recurring,
            reminder: reminder,
            description: description.trim()
        });
    }

    canAccept: title.trim() !== ""
    onAcceptBlocked: {
        showErrors = true;
        Notices.show(qsTr("Add a title first"));
    }
    onAccepted: app.saveEvent(event())
    onStatusChanged: if (status === PageStatus.Active && original === null && Window.activeFocusItem === dialog)
        titleField.forceActiveFocus()

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
                errorHighlight: dialog.showErrors && text.trim() === ""
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: locationField.focus = true
            }
            TextField {
                id: locationField

                objectName: "locationField"
                width: parent.width
                label: qsTr("Location")
                placeholderText: qsTr("Location")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: descriptionArea.focus = true
            }
            TextArea {
                id: descriptionArea

                objectName: "descriptionArea"
                width: parent.width
                label: qsTr("Description")
                placeholderText: qsTr("Description")
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
                label: qsTr("Starts")
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
            ValueButton {
                objectName: "endTimeButton"
                label: qsTr("Ends")
                visible: !dialog.allDay
                value: {
                    const time = Format.formatDate(new Date(2000, 0, 1, dialog.endHour, dialog.endMinute), Formatter.TimeValue);
                    return Logic.endsNextDay({ time: Logic.timeString(dialog.hour, dialog.minute), endTime: dialog.endTime }) ? qsTr("%1, next day").arg(time) : time;
                }
                onClicked: {
                    const picker = pageStack.push(timePickerComponent, { hour: dialog.endHour, minute: dialog.endMinute });
                    picker.accepted.connect(function () {
                        dialog.setEnd(picker.hour, picker.minute);
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
        }

        VerticalScrollDecorator {}
    }
}
