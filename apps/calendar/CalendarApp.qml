import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation
import "pages"

MApp {
    id: calendarApp
    appId: "calendar"
    appName: "Calendar"
    appIcon: "assets/icon.svg"

    property date currentDate: new Date()
    property var selectedDate: null
    property int currentView: 0

    Component.onCompleted: {
        CalendarStorage.init();
    }

    function createEvent(title, date, time, allDay, recurring) {
        var event = {
            title: title || "Untitled Event",
            date: date,
            time: time || "12:00",
            allDay: allDay || false,
            recurring: recurring || "none"
        };
        CalendarStorage.addEvent(event);
        return event;
    }

    function getEventsForDate(date) {
        return CalendarStorage.getEventsForDate(date);
    }

    function deleteEvent(id) {
        return CalendarStorage.deleteEvent(id);
    }

    property Item navStack: null

    navigationDepth: navStack ? navStack.depth : 0
    onBackPressed: {
        if (navStack && navStack.depth > 1) {
            navStack.pop();
        } else if (calendarApp.selectedDate !== null) {
            // If filtering by date, clear filter
            calendarApp.selectedDate = null;
        } else if (calendarApp.currentView === 1) {
            // If in list view (without filter), go back to month view
            calendarApp.currentView = 0;
        } else {
            // Let the shell handle closing the app if at root
            navigationDepth = 0; 
        }
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
                            label: "Month",
                            icon: "calendar"
                        },
                        {
                            label: "List",
                            icon: "list"
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

    // Helper to open detail page
    function openEventDetail(event) {
        if (navStack) {
            navStack.push("pages/EventDetailPage.qml", {
                "event": event,
                "onDelete": eventId => {
                    calendarApp.deleteEvent(eventId);
                }
            });
        }
    }
}
