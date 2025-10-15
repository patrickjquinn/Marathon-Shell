import QtQuick
import MarathonOS.Shell

Item {
    id: toggle
    width: Constants.touchTargetSmall
    height: 32
    
    property bool checked: false
    signal toggled(bool value)
    
    Rectangle {
        id: track
        anchors.fill: parent
        radius: 4
        border.width: 1
        border.color: checked ? Qt.rgba(20, 184, 166, 0.8) : Qt.rgba(255, 255, 255, 0.15)
        color: checked ? Qt.rgba(20, 184, 166, 0.2) : Qt.rgba(255, 255, 255, 0.05)
        layer.enabled: true
        
        Behavior on border.color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.03)
        }
    }
    
    Rectangle {
        id: switchHandle
        anchors.verticalCenter: parent.verticalCenter
        x: checked ? parent.width - width - 2 : 2
        width: 28
        height: 28
        radius: 3
        color: Colors.text
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.15)
        layer.enabled: true
        
        scale: mouseArea.pressed ? 0.95 : 1.0
        
        Behavior on x {
            NumberAnimation { 
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        
        Behavior on scale {
            NumberAnimation { 
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -8
        onClicked: {
            checked = !checked
            toggled(checked)
        }
    }
}

