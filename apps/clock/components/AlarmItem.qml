import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Theme

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
    signal clicked()
    
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
        
        MouseArea {
            anchors.fill: parent
            onClicked: alarmItem.clicked()
        }
        
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
                    color: alarmEnabled ? MColors.text : MColors.textSecondary
                    font.pixelSize: Constants.fontSizeXLarge
                    font.weight: Font.Bold
                }
                
                Text {
                    text: alarmLabel
                    color: MColors.textSecondary
                    font.pixelSize: Constants.fontSizeSmall
                }
            }
            
            MToggle {
                id: toggleSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: alarmEnabled
                onToggled: {
                    alarmItem.toggled()
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
            color: MColors.border
        }
    }
}

