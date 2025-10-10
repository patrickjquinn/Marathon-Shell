import QtQuick
import "../theme"

Item {
    id: toggle
    width: parent.width
    height: 60
    
    property string text: "Toggle"
    property bool checked: false
    property color accentColor: Colors.accent
    
    signal toggled(bool value)
    
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        
        Text {
            id: label
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: toggle.text
            color: "#000000"
            font.pixelSize: 22
            font.family: Typography.fontFamily
        }
        
        Rectangle {
            id: switchBackground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 80
            height: 40
            radius: 20
            color: checked ? accentColor : "#CCCCCC"
            
            Behavior on color {
                ColorAnimation { duration: 200 }
            }
            
            Rectangle {
                id: switchHandle
                anchors.verticalCenter: parent.verticalCenter
                x: checked ? parent.width - width - 4 : 4
                width: 32
                height: 32
                radius: 16
                color: "#FFFFFF"
                
                Behavior on x {
                    NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                }
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    checked = !checked
                    toggled(checked)
                }
            }
        }
    }
}

