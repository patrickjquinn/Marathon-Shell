import QtQuick
import "../theme"
import "../stores"
import "."

Item {
    id: statusBar
    height: 44
    
    Rectangle {
        anchors.fill: parent
        color: "#CC000000"  // 80% opacity black
        z: -1  // Behind content so it doesn't block touches
    }
    
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        
        Icon {
            name: SystemStatusStore.isCharging ? "battery-charging" : "battery"
            color: SystemStatusStore.batteryLevel < 20 ? Colors.error : Colors.text
            size: 18
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Text {
            text: SystemStatusStore.batteryLevel + "%"
            color: Colors.text
            font.pixelSize: 14
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    Text {
        anchors.centerIn: parent
        text: SystemStatusStore.timeString
        color: Colors.text
        font.pixelSize: 16
        font.weight: Font.Medium
    }
    
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        
        Icon {
            name: "signal"
            color: Colors.text
            size: 16
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.cellularStrength > 0
        }
        
        Icon {
            name: "wifi"
            color: SystemStatusStore.isWifiOn ? Colors.text : Colors.textTertiary
            size: 16
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}

