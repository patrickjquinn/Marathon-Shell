import QtQuick
import "../theme"

Item {
    id: root
    property string appName: ""
    property string appIcon: ""
    property color appColor: Colors.surface
    
    Rectangle {
        id: iconBg
        anchors.fill: parent
        anchors.margins: 6
        color: appColor
        radius: 8
        
        scale: touchArea.pressed ? 0.92 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: Theme.durationFast
                easing.type: Theme.easingStandard
            }
        }
        
        Column {
            anchors.centerIn: parent
            spacing: 4
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: appIcon
                font.pixelSize: 42
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: appName
                color: Colors.text
                font.pixelSize: Typography.sizeSmall - 2
                font.family: Typography.fontFamily
            }
        }
        
        MouseArea {
            id: touchArea
            anchors.fill: parent
            onClicked: {
                console.log("Launch:", appName)
            }
        }
    }
}

