import QtQuick
import "../theme"
import "."

Rectangle {
    id: listItem
    width: parent.width
    height: 80
    color: pressed ? "#F0F0F0" : "#FFFFFF"
    
    property string title: ""
    property string subtitle: ""
    property string time: ""
    property string iconSource: ""
    property color iconColor: Colors.accent
    property bool showDelete: false
    property bool pressed: false
    
    signal clicked()
    signal deleteClicked()
    
    Behavior on color {
        ColorAnimation { duration: 100 }
    }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16
        
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: 24
            color: iconColor
            opacity: 0.2
            
            Image {
                anchors.centerIn: parent
                source: iconSource
                width: 28
                height: 28
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }
        
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 48 - 100 - 32
            spacing: 4
            
            Text {
                text: title
                color: "#000000"
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.family: Typography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                text: subtitle
                color: "#666666"
                font.pixelSize: 16
                font.family: Typography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
        }
        
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: time
            color: "#999999"
            font.pixelSize: 14
            font.family: Typography.fontFamily
        }
        
        Rectangle {
            visible: showDelete
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 40
            color: "transparent"
            
            Icon {
                name: "x"
                color: "#999999"
                size: 24
                anchors.centerIn: parent
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: deleteClicked()
            }
        }
    }
    
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: "#E0E0E0"
    }
    
    MouseArea {
        anchors.fill: parent
        onPressed: listItem.pressed = true
        onReleased: listItem.pressed = false
        onCanceled: listItem.pressed = false
        onClicked: listItem.clicked()
    }
}

