import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import "./pages"

MApp {
    id: calendarApp
    appId: "calendar"
    appName: "Calendar"
    appIcon: "assets/icon.svg"
    
    property var events: []
    property int nextEventId: 1
    property date currentDate: new Date()
    
    Component.onCompleted: {
        loadEvents()
    }
    
    function loadEvents() {
        var savedEvents = SettingsManagerCpp.get("calendar/events", "[]")
        try {
            events = JSON.parse(savedEvents)
            if (events.length > 0) {
                nextEventId = Math.max(...events.map(e => e.id)) + 1
            }
        } catch (e) {
            Logger.error("CalendarApp", "Failed to load events: " + e)
            events = []
        }
    }
    
    function saveEvents() {
        var data = JSON.stringify(events)
        SettingsManagerCpp.set("calendar/events", data)
    }
    
    function createEvent(title, date, time, allDay) {
        var event = {
            id: nextEventId++,
            title: title || "Untitled Event",
            date: date,
            time: time || "12:00",
            allDay: allDay || false,
            timestamp: Date.now()
        }
        events.push(event)
        eventsChanged()
        saveEvents()
        return event
    }
    
    function deleteEvent(id) {
        for (var i = 0; i < events.length; i++) {
            if (events[i].id === id) {
                events.splice(i, 1)
                eventsChanged()
                saveEvents()
                return true
            }
        }
        return false
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        EventListPage {}
        
        MIconButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Constants.spacingLarge
            icon: "plus"
            size: Constants.touchTargetLarge
            variant: "primary"
            shape: "circular"
            onClicked: {
                var now = new Date()
                calendarApp.createEvent("New Event", Qt.formatDate(now, "yyyy-MM-dd"), Qt.formatTime(now, "HH:mm"), false)
            }
        }
    }
}

