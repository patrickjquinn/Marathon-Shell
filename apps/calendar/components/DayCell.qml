import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../CalendarLogic.js" as Logic

// A DatePicker day with a dot per event (up to three) under it.
MouseArea {
    id: cell

    required property int year
    required property int month
    required property int day
    required property int primaryMonth
    property DatePicker picker
    property var events: []

    readonly property date cellDate: new Date(year, month - 1, day, 12, 0, 0)
    readonly property int eventCount: Logic.eventsOn(events, cellDate).length
    readonly property bool inMonth: month === primaryMonth
    readonly property bool selected: picker && day === picker.day && month === picker.month && year === picker.year
    readonly property bool today: Logic.dateKey(cellDate) === Logic.dateKey(new Date())

    function select() {
        picker.date = cellDate;
    }

    width: picker ? picker.cellWidth : 0
    height: picker ? picker.cellHeight : 0
    activeFocusOnTab: inMonth
    Accessible.role: Accessible.Button
    Accessible.name: Format.formatDate(cellDate, Formatter.DateLong) + (eventCount > 0 ? ", " + (eventCount === 1 ? qsTr("1 event") : qsTr("%1 events").arg(eventCount)) : "")
    Accessible.selected: selected
    Accessible.onPressAction: select()
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true;
            cell.select();
        }
    }
    onClicked: select()

    Label {
        id: dayLabel

        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.paddingSmall
        text: cell.day.toLocaleString()
        color: cell.pressed && cell.containsMouse || cell.selected || cell.today ? Theme.highlightColor : cell.inMonth ? Theme.primaryColor : Theme.secondaryColor
    }

    Row {
        objectName: "eventDots"
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: dayLabel.baseline
            topMargin: Theme.paddingSmall
        }
        spacing: Theme.paddingSmall / 2
        visible: cell.eventCount > 0

        Repeater {
            model: Math.min(cell.eventCount, 3)

            Rectangle {
                width: Theme.paddingSmall
                height: width
                radius: width / 2
                color: cell.inMonth ? Theme.highlightColor : Theme.secondaryHighlightColor
            }
        }
    }

    FocusFrame {
        parent: cell
    }
}
