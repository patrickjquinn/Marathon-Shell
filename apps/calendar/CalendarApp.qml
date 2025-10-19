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
    property int currentView: 0
    
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
    
    function createEvent(title, date, time, allDay, recurring) {
        var event = {
            id: nextEventId++,
            title: title || "Untitled Event",
            date: date,
            time: time || "12:00",
            allDay: allDay || false,
            recurring: recurring || "none",
            timestamp: Date.now()
        }
        events.push(event)
        eventsChanged()
        saveEvents()
        return event
    }
    
    function getEventsForDate(date) {
        var dateStr = Qt.formatDate(date, "yyyy-MM-dd")
        var result = []
        
        for (var i = 0; i < events.length; i++) {
            var event = events[i]
            
            if (event.date === dateStr) {
                result.push(event)
            } else if (event.recurring !== "none") {
                var eventDate = new Date(event.date)
                var checkDate = new Date(date)
                
                if (event.recurring === "daily" && checkDate >= eventDate) {
                    result.push(event)
                } else if (event.recurring === "weekly" && checkDate >= eventDate) {
                    var daysDiff = Math.floor((checkDate - eventDate) / (1000 * 60 * 60 * 24))
                    if (daysDiff % 7 === 0) {
                        result.push(event)
                    }
                } else if (event.recurring === "monthly" && checkDate >= eventDate) {
                    if (checkDate.getDate() === eventDate.getDate()) {
                        result.push(event)
                    }
                }
            }
        }
        
        return result
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
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            Rectangle {
                width: parent.width
                height: Constants.touchTargetLarge
                color: MColors.surface
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }
                
                Row {
                    anchors.centerIn: parent
                    spacing: Constants.spacingMedium
                    
                    Repeater {
                        model: [
                            { label: "Month", icon: "calendar" },
                            { label: "List", icon: "list" }
                        ]
                        
                        Rectangle {
                            width: Constants.touchTargetLarge * 2
                            height: Constants.touchTargetMedium
                            radius: Constants.borderRadiusSharp
                            color: currentView === index ? MColors.accent : MColors.glass
                            border.width: Constants.borderWidthMedium
                            border.color: currentView === index ? MColors.accentBright : MColors.glassBorder
                            antialiasing: Constants.enableAntialiasing
                            
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Constants.borderWidthThin
                                radius: parent.radius - Constants.borderWidthThin
                                color: "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: currentView === index ? MColors.borderHighlight : MColors.borderInner
                                antialiasing: Constants.enableAntialiasing
                            }
                            
                            Row {
                                anchors.centerIn: parent
                                spacing: Constants.spacingSmall
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.icon
                                    size: Constants.iconSizeMedium
                                    color: currentView === index ? MColors.textOnAccent : MColors.text
                                }
                                
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    font.pixelSize: Constants.fontSizeMedium
                                    font.weight: currentView === index ? Font.DemiBold : Font.Normal
                                    color: currentView === index ? MColors.textOnAccent : MColors.text
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    currentView = index
                                    HapticService.light()
                                }
                            }
                        }
                    }
                }
            }
            
            StackLayout {
                width: parent.width
                height: parent.height - parent.children[0].height
                currentIndex: currentView
                
                CalendarGridPage {
                    id: gridPage
                }
                
                EventListPage {
                    id: listPage
                }
            }
        }
        
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
                calendarApp.createEvent("New Event", Qt.formatDate(now, "yyyy-MM-dd"), Qt.formatTime(now, "HH:mm"), false, "none")
            }
        }
    }
}

