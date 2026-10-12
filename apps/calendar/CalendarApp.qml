pragma ComponentBehavior: Bound
import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

MApp {
    id: calendarApp

    property date currentDate: new Date()
    property var selectedDate: new Date()
    property int currentView: 1
    property var navStack: null

    signal eventsChanged

    function createEvent(title, date, time, allDay, recurring) {
        var event = {
            "title": title || "Untitled Event",
            "date": date,
            "time": time || "12:00",
            "allDay": allDay || false,
            "recurring": recurring || "none"
        };
        return calendarStorage.addEvent(event).id !== undefined;
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
        navStack.push("pages/EventDetailPage.qml", {
            "event": event,
            "deleteCallback": eventId => {
                calendarApp.deleteEvent(eventId);
            }
        });
    }

    function openEventCreation(day) {
        navStack.push("pages/EventCreationPage.qml", {
            "initialDate": day,
            "saveCallback": event => calendarApp.createEvent(event.title, event.date, event.time, event.allDay, event.recurring)
        });
    }

    appId: "calendar"
    appName: "Calendar"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        calendarStorage.init();
    }
    navigationDepth: {
        if (!navStack)
            return 0;
        if (navStack.depth > 1)
            return navStack.depth - 1 + (navStack.currentItem.backLayers || 0);
        return selectedDate !== null || currentView !== 1 ? 1 : 0;
    }
    onBackPressed: {
        if (navStack.depth > 1) {
            if (navStack.currentItem.backLayers > 0)
                navStack.currentItem.handleBack();
            else
                navStack.pop();
        } else if (calendarApp.selectedDate !== null) {
            calendarApp.selectedDate = null;
        } else {
            calendarApp.currentView = 1;
        }
    }

    CalendarStorage {
        id: calendarStorage

        onDataChanged: calendarApp.eventsChanged()
        onEventsChanged: calendarApp.eventsChanged()
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

                    EventListPage {
                        id: listPage

                        app: calendarApp
                    }

                    CalendarGridPage {
                        id: gridPage

                        app: calendarApp
                    }

                    Loader {
                        active: calendarApp.currentView === 2

                        sourceComponent: YearPage {
                            year: gridPage.currentYear
                            onMonthChosen: (year, month) => {
                                gridPage.showMonth(year, month);
                                calendarApp.currentView = 1;
                            }
                        }
                    }

                    Loader {
                        active: calendarApp.currentView === 3

                        sourceComponent: EventSearchPage {
                            events: calendarStorage.events
                            onEventChosen: event => calendarApp.openEventDetail(event)
                        }
                    }
                }

                MTabBar {
                    id: tabBar

                    width: parent.width
                    activeTab: calendarApp.currentView
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
                            "icon": "squares-four"
                        },
                        {
                            "label": "Search",
                            "icon": "magnifying-glass"
                        }
                    ]
                    onTabSelected: index => {
                        HapticService.light();
                        calendarApp.currentView = index;
                    }
                }
            }

            MFloatingActionButton {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: MSpacing.lg
                anchors.bottomMargin: tabBar.height + MSpacing.lg
                visible: calendarApp.currentView !== 3
                label: "New event"
                onClicked: calendarApp.openEventCreation(gridPage.selectedDate)
            }
        }
    }
}
