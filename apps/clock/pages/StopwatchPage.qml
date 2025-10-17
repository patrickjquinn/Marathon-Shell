import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core

Item {
    id: stopwatchPage
    
    property int elapsedMs: 0
    property bool isRunning: false
    property var laps: []
    
    Timer {
        id: stopwatchTimer
        interval: 10
        running: isRunning
        repeat: true
        onTriggered: {
            elapsedMs += 10
        }
    }
    
    function formatTime(ms) {
        var totalSeconds = Math.floor(ms / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        var centiseconds = Math.floor((ms % 1000) / 10)
        return (minutes < 10 ? "0" : "") + minutes + ":" +
               (seconds < 10 ? "0" : "") + seconds + "." +
               (centiseconds < 10 ? "0" : "") + centiseconds
    }
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Column {
            width: parent.width
            height: parent.height * 0.4
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingXLarge
            
            Item { height: Constants.spacingLarge; width: 1 }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: formatTime(elapsedMs)
                color: Colors.text
                font.pixelSize: Constants.fontSizeHuge * 1.2
                font.weight: Font.Bold
            }
            
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingLarge
                
                MButton {
                    text: isRunning ? "Lap" : "Start"
                    variant: "primary"
                    onClicked: {
                        HapticService.light()
                        if (isRunning) {
                            laps.push(elapsedMs)
                            lapsChanged()
                        } else {
                            isRunning = true
                        }
                    }
                }
                
                MButton {
                    text: isRunning ? "Stop" : "Reset"
                    variant: isRunning ? "danger" : "secondary"
                    onClicked: {
                        HapticService.light()
                        if (isRunning) {
                            isRunning = false
                        } else {
                            elapsedMs = 0
                            laps = []
                        }
                    }
                }
            }
        }
        
        Rectangle {
            width: parent.width
            height: Constants.borderWidthThin
            color: Colors.border
            visible: laps.length > 0
        }
        
        ListView {
            width: parent.width
            height: parent.height * 0.6
            clip: true
            model: laps
            visible: laps.length > 0
            
            delegate: Item {
                width: parent.width
                height: Constants.touchTargetMedium
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingLarge
                    anchors.rightMargin: Constants.spacingLarge
                    spacing: Constants.spacingMedium
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Lap " + (index + 1)
                        color: Colors.text
                        font.pixelSize: Constants.fontSizeMedium
                        width: parent.width * 0.3
                    }
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: formatTime(modelData)
                        color: Colors.accent
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.DemiBold
                    }
                }
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Constants.spacingLarge
                    anchors.rightMargin: Constants.spacingLarge
                    height: Constants.borderWidthThin
                    color: Colors.border
                }
            }
        }
    }
}

