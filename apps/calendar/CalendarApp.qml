import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
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
        var savedEvents = SettingsManager.value("calendar/events", "[]")
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
        SettingsManager.setValue("calendar/events", data)
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
        color: Colors.background
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            Rectangle {
                width: parent.width
                height: Constants.actionBarHeight
                color: Colors.surface
                z: 10
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingLarge
                    anchors.rightMargin: Constants.spacingLarge
                    spacing: Constants.spacingMedium
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(currentDate, "MMMM yyyy")
                        color: Colors.text
                        font.pixelSize: Constants.fontSizeLarge
                        font.weight: Font.Bold
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Today"
                        variant: "secondary"
                        onClicked: {
                            currentDate = new Date()
                        }
                    }
                }
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: Colors.border
                }
            }
            
            EventListPage {
                width: parent.width
                height: parent.height - Constants.actionBarHeight
            }
        }
        
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Constants.spacingLarge
            width: Constants.touchTargetLarge
            height: Constants.touchTargetLarge
            radius: width / 2
            color: Colors.accent
            
            Icon {
                anchors.centerIn: parent
                name: "calendar"
                size: Constants.iconSizeMedium
                color: Colors.background
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    HapticService.light()
                    var now = new Date()
                    calendarApp.createEvent("New Event", Qt.formatDate(now, "yyyy-MM-dd"), Qt.formatTime(now, "HH:mm"), false)
                }
            }
        }
    }
}

