import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import "./pages"
import "./components" as ClockComponents

MApp {
    id: clockApp
    appId: "clock"
    appName: "Clock"
    // appIcon loaded from registry - don't override here
    
    property var alarms  // No initial binding - set by loadAlarms()
    property int nextAlarmId: 1
    
    Component.onCompleted: {
        loadAlarms()
    }
    
    function loadAlarms() {
        if (typeof AlarmManager !== 'undefined') {
            alarms = AlarmManager.alarms
        } else {
            var savedAlarms = SettingsManagerCpp.get("clock/alarms", "[]")
            try {
                alarms = JSON.parse(savedAlarms)
                if (alarms.length > 0) {
                    nextAlarmId = Math.max(...alarms.map(a => parseInt(a.id) || 0)) + 1
                }
            } catch (e) {
                Logger.error("ClockApp", "Failed to load alarms: " + e)
                alarms = []  // Fallback to empty array on error
            }
        }
        alarmsChanged()
    }
    
    function saveAlarms() {
        var data = JSON.stringify(alarms)
        SettingsManagerCpp.set("clock/alarms", data)
    }
    
    function createAlarm(hour, minute, label, enabled) {
        var timeString = _padZero(hour) + ":" + _padZero(minute)
        var repeat = []
        
        if (typeof AlarmManager !== 'undefined') {
            var alarmId = AlarmManager.createAlarm(timeString, label, repeat, {
                vibrate: true,
                snoozeEnabled: true,
                snoozeDuration: 10
            })
            
            loadAlarms()
            return { id: alarmId, hour: hour, minute: minute, label: label, enabled: true, repeat: repeat }
        } else {
            var alarm = {
                id: String(nextAlarmId++),
                time: timeString,
                hour: hour,
                minute: minute,
                label: label || "Alarm",
                enabled: enabled !== undefined ? enabled : true,
                repeat: []
            }
            alarms.push(alarm)
            alarmsChanged()
            saveAlarms()
            return alarm
        }
    }
    
    function updateAlarm(id, hour, minute, label, enabled, repeat) {
        var timeString = _padZero(hour) + ":" + _padZero(minute)
        
        if (typeof AlarmManager !== 'undefined') {
            var repeatDays = []
            if (repeat) {
                for (var i = 0; i < repeat.length; i++) {
                    if (repeat[i]) {
                        repeatDays.push(i)
                    }
                }
            }
            
            AlarmManager.updateAlarm(id, {
                time: timeString,
                label: label,
                enabled: enabled,
                repeat: repeatDays
            })
            
            loadAlarms()
        } else {
            for (var i = 0; i < alarms.length; i++) {
                if (alarms[i].id === id) {
                    alarms[i].time = timeString
                    alarms[i].hour = hour
                    alarms[i].minute = minute
                    alarms[i].label = label
                    alarms[i].enabled = enabled
                    if (repeat) alarms[i].repeat = repeat
                    alarmsChanged()
                    saveAlarms()
                    return true
                }
            }
        }
        return true
    }
    
    function deleteAlarm(id) {
        if (typeof AlarmManager !== 'undefined') {
            AlarmManager.deleteAlarm(id)
            loadAlarms()
        } else {
            for (var i = 0; i < alarms.length; i++) {
                if (alarms[i].id === id) {
                    alarms.splice(i, 1)
                    alarmsChanged()
                    saveAlarms()
                    return true
                }
            }
        }
        return true
    }
    
    function toggleAlarm(id) {
        if (typeof AlarmManager !== 'undefined') {
            AlarmManager.toggleAlarm(id)
            loadAlarms()
        } else {
            for (var i = 0; i < alarms.length; i++) {
                if (alarms[i].id === id) {
                    alarms[i].enabled = !alarms[i].enabled
                    alarmsChanged()
                    saveAlarms()
                    return true
                }
            }
        }
        return true
    }
    
    function _padZero(num) {
        return (num < 10 ? "0" : "") + num
    }
    
    Connections {
        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null
        enabled: typeof AlarmManager !== 'undefined'
        
        function onAlarmCreated() {
            loadAlarms()
        }
        
        function onAlarmUpdated() {
            loadAlarms()
        }
        
        function onAlarmDeleted() {
            loadAlarms()
        }
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            // Main content area
            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: tabBar.currentIndex
                
                ClockPage {
                    id: clockPage
                }
                
                AlarmPage {
                    id: alarmPage
                }
                
                TimerPage {
                    id: timerPage
                }
                
                StopwatchPage {
                    id: stopwatchPage
                }
            }
            
            // Bottom tab bar - BB10 style
            Rectangle {
                id: tabBar
                width: parent.width
                height: Constants.actionBarHeight
                color: MColors.surface
                
                property int currentIndex: 0
                
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 0
                    spacing: 0
                    
                    Repeater {
                        model: [
                            { icon: "clock", label: "Clock" },
                            { icon: "bell", label: "Alarm" },
                            { icon: "timer", label: "Timer" },
                            { icon: "stopwatch", label: "Stopwatch" }
                        ]
                        
                        Rectangle {
                            width: tabBar.width / 4
                            height: tabBar.height
                            color: "transparent"
                            
                            // Active indicator bar - BB10 style top accent line
                            Rectangle {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8
                                height: Constants.borderWidthThick
                                color: MColors.accent
                                opacity: tabBar.currentIndex === index ? 1.0 : 0.0
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: Constants.animationFast }
                                }
                            }
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: Constants.spacingXSmall
                                
                                ClockComponents.ClockIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: modelData.icon
                                    size: Constants.iconSizeMedium
                                    color: tabBar.currentIndex === index ? MColors.accent : MColors.textSecondary
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                                
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: Constants.fontSizeXSmall
                                    color: tabBar.currentIndex === index ? MColors.accent : MColors.textSecondary
                                    font.weight: tabBar.currentIndex === index ? Font.DemiBold : Font.Normal
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light()
                                    tabBar.currentIndex = index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
