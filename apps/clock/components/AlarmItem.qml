import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Item {
    id: alarmItem
    height: Constants.touchTargetLarge + Constants.spacingLarge
    
    property int alarmId: -1
    property int alarmHour: 0
    property int alarmMinute: 0
    property string alarmLabel: "Alarm"
    property bool alarmEnabled: true
    
    signal toggled()
    signal deleted()
    
    function formatTime(hour, minute) {
        var h = hour
        var suffix = "AM"
        if (h >= 12) {
            suffix = "PM"
            if (h > 12) h -= 12
        }
        if (h === 0) h = 12
        return h + ":" + (minute < 10 ? "0" : "") + minute + " " + suffix
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingLarge
        anchors.rightMargin: Constants.spacingLarge
        color: "transparent"
        
        Row {
            anchors.fill: parent
            anchors.margins: Constants.spacingMedium
            spacing: Constants.spacingMedium
            
            Column {
                width: parent.width - toggleSwitch.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Constants.spacingXSmall
                
                Text {
                    text: formatTime(alarmHour, alarmMinute)
                    color: alarmEnabled ? Colors.text : Colors.textSecondary
                    font.pixelSize: Constants.fontSizeXLarge
                    font.weight: Font.Bold
                }
                
                Text {
                    text: alarmLabel
                    color: Colors.textSecondary
                    font.pixelSize: Constants.fontSizeSmall
                }
            }
            
            Rectangle {
                id: toggleSwitch
                anchors.verticalCenter: parent.verticalCenter
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMinimum - Constants.spacingMedium
                radius: height / 2
                color: alarmEnabled ? Colors.accent : Colors.surfaceLight
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
                
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: alarmEnabled ? parent.width - width - Constants.spacingXSmall : Constants.spacingXSmall
                    width: parent.height - Constants.spacingXSmall * 2
                    height: width
                    radius: width / 2
                    color: Colors.background
                    
                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light()
                        alarmItem.toggled()
                    }
                }
            }
        }
        
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Constants.spacingMedium
            anchors.rightMargin: Constants.spacingMedium
            height: Constants.borderWidthThin
            color: Colors.border
        }
    }
}

