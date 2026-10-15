import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    property date now: new Date()

    function setClock(date) {
        Settings.setSystemTime(date.getTime());
        now = date;
    }

    function pickTime() {
        const dialog = pageStack.push(timePickerComponent, {
            hour: now.getHours(),
            minute: now.getMinutes(),
            hourMode: Settings.timeFormat === "24h" ? DateTime.TwentyFourHours : DateTime.TwelveHours
        });
        dialog.accepted.connect(() => {
            const d = new Date();
            d.setHours(dialog.hour, dialog.minute, 0, 0);
            page.setClock(d);
        });
    }

    function pickDate() {
        const dialog = pageStack.push(datePickerComponent, { date: now });
        dialog.accepted.connect(() => {
            const d = new Date();
            d.setFullYear(dialog.year, dialog.month - 1, dialog.day);
            page.setClock(d);
        });
    }

    Component {
        id: datePickerComponent

        DatePickerDialog {}
    }
    Component {
        id: timePickerComponent

        TimePickerDialog {}
    }

    Connections {
        target: Settings

        function onDateTimeChangeFailed(reason) {
            Notices.show(qsTr("Couldn't change the date and time"));
            page.now = new Date();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: page.status === PageStatus.Active
        onTriggered: page.now = new Date()
    }

    TimeZoneList {
        id: zones
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Date and time")
            }
            TextSwitch {
                objectName: "automaticSwitch"
                text: qsTr("Automatic update")
                description: qsTr("Set the time from the network")
                automaticCheck: false
                checked: Settings.automaticTime
                onClicked: Settings.automaticTime = !Settings.automaticTime
            }
            ValueButton {
                objectName: "timeButton"
                label: qsTr("Time")
                value: Qt.formatTime(page.now, Settings.timeFormat === "24h" ? "HH:mm" : "h:mm AP")
                enabled: !Settings.automaticTime
                onClicked: page.pickTime()
            }
            ValueButton {
                objectName: "dateButton"
                label: qsTr("Date")
                value: Format.formatDate(page.now, Formatter.DateLong)
                enabled: !Settings.automaticTime
                onClicked: page.pickDate()
            }
            TextSwitch {
                objectName: "clockSwitch"
                text: qsTr("24-hour clock")
                description: Qt.formatTime(page.now, Settings.timeFormat === "24h" ? "HH:mm" : "h:mm AP")
                automaticCheck: false
                checked: Settings.timeFormat === "24h"
                onClicked: Settings.timeFormat = checked ? "12h" : "24h"
            }
            TextSwitch {
                objectName: "automaticZoneSwitch"
                text: qsTr("Automatic time zone")
                description: qsTr("Set the time zone from your location while Location is on")
                automaticCheck: false
                checked: Settings.automaticTimeZone
                onClicked: Settings.automaticTimeZone = !Settings.automaticTimeZone
            }
            ValueButton {
                objectName: "zoneButton"
                label: qsTr("Time zone")
                value: zones.displayName(Settings.timeZone || "UTC")
                enabled: !Settings.automaticTimeZone
                onClicked: pageStack.push(Qt.resolvedUrl("TimeZonePage.qml"))
            }
        }

        VerticalScrollDecorator {}
    }
}
