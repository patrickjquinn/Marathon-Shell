import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MApp {
    id: calendarApp

    property date currentDate: new Date()
    property var selectedDate: null
    property int currentView: 0
    property StackView navStack: null

    signal eventsChanged

    function createEvent(title, date, time, allDay, recurring) {
        var event = {
            "title": title || "Untitled Event",
            "date": date,
            "time": time || "12:00",
            "allDay": allDay || false,
            "recurring": recurring || "none"
        };
        calendarStorage.addEvent(event);
        return event;
    }

    function getEventsForDate(date) {
        return calendarStorage.getEventsForDate(date);
    }

    function getAllEvents() {
        return calendarStorage.events;
    }

    function deleteEvent(id) {
        return calendarStorage.deleteEvent(id);
    }

    function openEventDetail(event) {
        if (navStack)
            navStack.push("pages/EventDetailPage.qml", {
                "event": event,
                "deleteCallback": eventId => {
                    calendarApp.deleteEvent(eventId);
                }
            });
    }

    appId: "calendar"
    appName: "Calendar"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        calendarStorage.init();
    }
    navigationDepth: navStack ? navStack.depth : 0
    onBackPressed: {
        if (navStack && navStack.depth > 1)
            navStack.pop();
        else if (calendarApp.selectedDate !== null)
            calendarApp.selectedDate = null;
        else if (calendarApp.currentView === 1)
            calendarApp.currentView = 0;
        else
            navigationDepth = 0;
    }

    CalendarStorage {
        id: calendarStorage

        onDataChanged: calendarApp.eventsChanged()
    }

    content: MStackView {
        id: stackView

        anchors.fill: parent
        Component.onCompleted: calendarApp.navStack = stackView

        initialItem: Rectangle {
            color: MColors.background

            Column {
                anchors.fill: parent
                spacing: 0

                StackLayout {
                    width: parent.width
                    height: parent.height - tabBar.height
                    currentIndex: calendarApp.currentView

                    CalendarGridPage {
                        id: gridPage
                    }

                    EventListPage {
                        id: listPage
                    }
                }

                MTabBar {
                    id: tabBar

                    width: parent.width
                    // Map four UI tabs onto the two pages we ship for now.
                    // Day → list page (page 1), Month → grid page (page 0),
                    // Year/Search defer to Month until those panes ship.
                    activeTab: calendarApp.currentView === 1 ? 0 : 1
                    tabs: [
                        {
                            "label": "Day",
                            "icon": "clock"
                        },
                        {
                            "label": "Month",
                            "icon": "calendar"
                        },
                        {
                            "label": "Year",
                            "icon": "archive"
                        },
                        {
                            "label": "Search",
                            "icon": "search"
                        }
                    ]
                    onTabSelected: index => {
                        HapticService.light();
                        // Day=0 → list pane (index 1 in our StackLayout)
                        // Month=1 → grid pane (index 0)
                        // Year/Search default to grid until panes land.
                        calendarApp.currentView = (index === 0) ? 1 : 0;
                    }
                }
            }
            // FAB removed — compose now lives in the page header (JSX
            // ref-calendar moves the action up to the title bar).
        }
    }
}
