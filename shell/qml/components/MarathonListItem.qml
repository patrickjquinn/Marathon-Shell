import QtQuick
import MarathonOS.Shell

Rectangle {
    id: listItem
    width: parent.width
    height: Constants.hubHeaderHeight
    color: root.pressed ? Colors.surfaceLight : Colors.surface
    
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
        anchors.leftMargin: Constants.spacingMedium
        anchors.rightMargin: Constants.spacingMedium
        spacing: Constants.spacingMedium
        
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: Colors.cornerRadiusCircle
            color: root.iconColor
            opacity: 0.2
            
            Image {
                anchors.centerIn: parent
                source: root.iconSource
                width: 28
                height: 28
                fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
                smooth: true
            }
        }
        
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 48 - 100 - 32
            spacing: 4
            
            Text {
                text: root.title
                color: Colors.text
                font.pixelSize: Typography.sizeBody
                font.weight: Font.DemiBold
                font.family: Typography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                text: root.subtitle
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeSmall
                font.family: Typography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
        }
        
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.time
            color: Colors.textTertiary
            font.pixelSize: Typography.sizeSmall
            font.family: Typography.fontFamily
        }
        
        Rectangle {
            visible: root.showDelete
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 40
            color: "transparent"
            
            Icon {
                name: "x"
                color: Colors.textSecondary
                size: Constants.iconSizeMedium
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
        color: Colors.border
    }
    
    MouseArea {
        anchors.fill: parent
        onPressed: listItem.pressed = true
        onReleased: listItem.pressed = false
        onCanceled: listItem.pressed = false
        onClicked: listItem.clicked()
    }
}

