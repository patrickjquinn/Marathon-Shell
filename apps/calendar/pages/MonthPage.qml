pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../CalendarLogic.js" as Logic
import "../components"

Page {
    id: page

    property var app
    property alias date: picker.date
    readonly property var dayEvents: Logic.eventsOn(app.events, date)
    readonly property bool showingToday: Logic.dateKey(date) === Logic.dateKey(new Date())

    function showDate(d) {
        picker.date = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12, 0, 0);
    }

    function openYear() {
        const year = pageStack.push(Qt.resolvedUrl("YearPage.qml"), { year: date.getFullYear() });
        year.monthChosen.connect(function (y, m) {
            page.showDate(new Date(y, m, 1));
            pageStack.pop(page);
        });
        return year;
    }

    SilicaFlickable {
        id: flickable

        objectName: "monthView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "agendaItem"
                text: qsTr("All events")
                onClicked: pageStack.push(Qt.resolvedUrl("AgendaPage.qml"), { app: page.app })
            }
            MenuItem {
                objectName: "yearItem"
                text: qsTr("Year view")
                onClicked: page.openYear()
            }
            MenuItem {
                objectName: "todayItem"
                text: qsTr("Go to today")
                visible: !page.showingToday
                onClicked: page.showDate(new Date())
            }
            MenuItem {
                objectName: "newEventItem"
                text: qsTr("New event")
                onClicked: page.app.newEvent(page.date)
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                id: header

                objectName: "monthHeader"
                title: Qt.locale().standaloneMonthName(page.date.getMonth())
                description: page.date.getFullYear()
            }

            DatePicker {
                id: picker

                objectName: "datePicker"
                width: parent.width
                // Without the week column the margins let the next month peek in.
                leftMargin: 0
                rightMargin: 0
                // Six weeks fit on a short screen.
                cellHeight: Math.min(cellWidth, Math.floor((page.height - header.height - dayRowHeight) / 6))
                daysVisible: true
                weeksVisible: false
                monthYearVisible: false
                delegate: Component {
                    DayCell {
                        picker: picker
                        events: page.app.events
                    }
                }
            }

            SectionHeader {
                objectName: "dayHeader"
                text: page.showingToday ? qsTr("Today") : Format.formatDate(page.date, Formatter.DateLong)
            }

            Repeater {
                objectName: "dayEvents"
                model: page.dayEvents

                EventItem {
                    app: page.app
                }
            }

            Label {
                objectName: "noEvents"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.dayEvents.length === 0
                text: qsTr("No events")
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
            }
        }

        VerticalScrollDecorator {}
    }
}
