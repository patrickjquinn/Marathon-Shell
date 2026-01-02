import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "stores"

MApp {
    id: calendarApp

    property date currentDate: new Date()
    property var selectedDate: null
    property int currentView: 0
    property Item navStack: null

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

    function deleteEvent(id) {
        return calendarStorage.deleteEvent(id);
    }

    // Helper to open detail page
    function openEventDetail(event) {
        if (navStack)
            navStack.push("pages/EventDetailPage.qml", {
                "event": event,
                "onDelete": eventId => {
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
        // If filtering by date, clear filter
        // If in list view (without filter), go back to month view
        // Let the shell handle closing the app if at root

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
    }

    content: StackView {
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
                    activeTab: calendarApp.currentView
                    tabs: [
                        {
                            "label": "Month",
                            "icon": "calendar"
                        },
                        {
                            "label": "List",
                            "icon": "list"
                        }
                    ]
                    onTabSelected: index => {
                        HapticService.light();
                        calendarApp.currentView = index;
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
                    stackView.push("pages/EventCreationPage.qml", {
                        "onSave": event => {
                            calendarApp.createEvent(event.title, event.date, event.time, event.allDay, event.recurring);
                        }
                    });
                }
            }
        }

        // Transitions
        pushEnter: Transition {
            PropertyAnimation {
                property: "x"
                from: stackView.width
                to: 0
                duration: MMotion.md
                easing.type: Easing.OutCubic
            }
        }

        pushExit: Transition {
            PropertyAnimation {
                property: "x"
                from: 0
                to: -stackView.width * 0.3
                duration: MMotion.md
                easing.type: Easing.OutCubic
            }
        }

        popEnter: Transition {
            PropertyAnimation {
                property: "x"
                from: -stackView.width * 0.3
                to: 0
                duration: MMotion.md
                easing.type: Easing.OutCubic
            }
        }

        popExit: Transition {
            PropertyAnimation {
                property: "x"
                from: 0
                to: stackView.width
                duration: MMotion.md
                easing.type: Easing.OutCubic
            }
        }
    }
}
