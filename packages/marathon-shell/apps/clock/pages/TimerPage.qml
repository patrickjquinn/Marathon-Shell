import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core

Item {
    id: timerPage
    
    property int remainingSeconds: 0
    property bool isRunning: false
    property int totalSeconds: 0
    
    Timer {
        id: countdownTimer
        interval: 1000
        running: isRunning
        repeat: true
        onTriggered: {
            if (remainingSeconds > 0) {
                remainingSeconds--
            } else {
                isRunning = false
                HapticService.strong()
            }
        }
    }
    
    function formatTime(seconds) {
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        var s = seconds % 60
        
        if (h > 0) {
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        } else {
            return m + ":" + (s < 10 ? "0" : "") + s
        }
    }
    
    Flickable {
        anchors.fill: parent
        contentHeight: mainColumn.height
        clip: true
        
        Column {
            id: mainColumn
            width: parent.width
            spacing: Constants.spacingXLarge * 2
            topPadding: Constants.spacingXLarge * 2
            bottomPadding: Constants.spacingLarge
            
            // Timer display
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: formatTime(remainingSeconds)
                color: Colors.text
                font.pixelSize: Constants.fontSizeHuge * 1.8
                font.weight: Font.Light
            }
            
            // Quick timer buttons
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingMedium
                visible: !isRunning && remainingSeconds === 0
                width: Math.min(parent.width - Constants.spacingLarge * 2, Constants.screenWidth * 0.8)
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Quick Timers"
                    color: Colors.textSecondary
                    font.pixelSize: Constants.fontSizeMedium
                }
                
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 3
                    spacing: Constants.spacingMedium
                    width: parent.width
                    
                    Repeater {
                        model: [1, 3, 5, 10, 15, 30]
                        
                        MButton {
                            width: (parent.width - parent.spacing * 2) / 3
                            text: modelData + " min"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                remainingSeconds = modelData * 60
                                totalSeconds = remainingSeconds
                            }
                        }
                    }
                }
            }
            
            // Control buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingLarge
                visible: remainingSeconds > 0
                
                MButton {
                    text: isRunning ? "Pause" : "Start"
                    variant: "primary"
                    onClicked: {
                        HapticService.light()
                        isRunning = !isRunning
                    }
                }
                
                MButton {
                    text: "Reset"
                    variant: "secondary"
                    onClicked: {
                        HapticService.light()
                        isRunning = false
                        remainingSeconds = 0
                        totalSeconds = 0
                    }
                }
            }
        }
    }
}
