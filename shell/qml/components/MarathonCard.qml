import QtQuick
import MarathonOS.Shell

Rectangle {
    id: card
    color: Qt.rgba(255, 255, 255, 0.04)
    radius: 4
    
    property alias content: contentItem.children
    property int elevation: 1
    property bool hoverable: false
    
    border.width: 1
    border.color: Qt.rgba(255, 255, 255, 0.12)
    layer.enabled: true
    
    Behavior on border.color {
        ColorAnimation { duration: 150 }
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.03)
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: 0
    }
}

