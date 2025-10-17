import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"
import "../components" as ClockComponents

Item {
    id: alarmPage
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Item {
            width: parent.width
            height: parent.height
            
            ListView {
                id: alarmsList
                anchors.fill: parent
                anchors.topMargin: Constants.spacingMedium
                clip: true
                model: clockApp.alarms
                spacing: 0
                
                delegate: AlarmItem {
                    width: alarmsList.width
                    alarmId: modelData.id
                    alarmHour: modelData.time ? _getHour(modelData.time) : (modelData.hour || 0)
                    alarmMinute: modelData.time ? _getMinute(modelData.time) : (modelData.minute || 0)
                    alarmLabel: modelData.label
                    alarmEnabled: modelData.enabled
                    
                    onToggled: {
                        clockApp.toggleAlarm(alarmId)
                    }
                    
                    onDeleted: {
                        clockApp.deleteAlarm(alarmId)
                    }
                    
                    function _getHour(timeStr) {
                        if (!timeStr) return 0
                        var parts = timeStr.split(":")
                        return parseInt(parts[0])
                    }
                    
                    function _getMinute(timeStr) {
                        if (!timeStr) return 0
                        var parts = timeStr.split(":")
                        return parseInt(parts[1])
                    }
                }
                
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.8, Constants.screenWidth * 0.6)
                    height: emptyColumn.height
                    color: "transparent"
                    visible: alarmsList.count === 0
                    
                    Column {
                        id: emptyColumn
                        anchors.centerIn: parent
                        spacing: Constants.spacingLarge
                        
                        ClockComponents.ClockIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "clock"
                            size: Constants.iconSizeXLarge * 2
                            color: Colors.textSecondary
                            opacity: 0.5
                        }
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No alarms set"
                            color: Colors.textSecondary
                            font.pixelSize: Constants.fontSizeLarge
                            font.weight: Font.Medium
                        }
                        
                        Text {
                            width: parent.width
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Tap the + button to create an alarm"
                            color: Colors.textSecondary
                            font.pixelSize: Constants.fontSizeMedium
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
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
        
        ClockComponents.ClockIcon {
            anchors.centerIn: parent
            name: "clock"
            size: Constants.iconSizeMedium
            color: Colors.background
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                HapticService.light()
                var now = new Date()
                clockApp.createAlarm(now.getHours(), now.getMinutes(), "Alarm", true)
            }
        }
    }
}

