import QtQuick
import QtQuick.Layouts
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

    property var events: []
    property int nextEventId: 1
    property date currentDate: new Date()
    property int currentView: 0

    Component.onCompleted: {
        loadEvents();
    }

    function loadEvents() {
        var savedEvents = SettingsManagerCpp.get("calendar/events", "[]");
        try {
            events = JSON.parse(savedEvents);
            if (events.length > 0) {
                nextEventId = Math.max(...events.map(e => e.id)) + 1;
            }
        } catch (e) {
            Logger.error("CalendarApp", "Failed to load events: " + e);
            events = [];
        }
    }

    function saveEvents() {
        var data = JSON.stringify(events);
        SettingsManagerCpp.set("calendar/events", data);
    }

    function createEvent(title, date, time, allDay, recurring) {
        var event = {
            id: nextEventId++,
            title: title || "Untitled Event",
            date: date,
            time: time || "12:00",
            allDay: allDay || false,
            recurring: recurring || "none",
            timestamp: Date.now()
        };
        events.push(event);
        eventsChanged();
        saveEvents();
        return event;
    }

    function getEventsForDate(date) {
        var dateStr = Qt.formatDate(date, "yyyy-MM-dd");
        var result = [];

        for (var i = 0; i < events.length; i++) {
            var event = events[i];

            if (event.date === dateStr) {
                result.push(event);
            } else if (event.recurring !== "none") {
                var eventDate = new Date(event.date);
                var checkDate = new Date(date);

                if (event.recurring === "daily" && checkDate >= eventDate) {
                    result.push(event);
                } else if (event.recurring === "weekly" && checkDate >= eventDate) {
                    var daysDiff = Math.floor((checkDate - eventDate) / (1000 * 60 * 60 * 24));
                    if (daysDiff % 7 === 0) {
                        result.push(event);
                    }
                } else if (event.recurring === "monthly" && checkDate >= eventDate) {
                    if (checkDate.getDate() === eventDate.getDate()) {
                        result.push(event);
                    }
                }
            }
        }

        return result;
    }

    function deleteEvent(id) {
        for (var i = 0; i < events.length; i++) {
            if (events[i].id === id) {
                events.splice(i, 1);
                eventsChanged();
                saveEvents();
                return true;
            }
        }
        return false;
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            anchors.fill: parent
            spacing: 0

            property int currentView: 0

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentView

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
                activeTab: parent.currentView

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
                    tabBar.parent.currentView = index;
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
                var now = new Date();
                calendarApp.createEvent("New Event", Qt.formatDate(now, "yyyy-MM-dd"), Qt.formatTime(now, "HH:mm"), false, "none");
            }
        }
    }
}
