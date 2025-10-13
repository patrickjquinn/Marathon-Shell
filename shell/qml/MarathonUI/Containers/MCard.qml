import QtQuick
import "../Theme"

Rectangle {
    id: root
    
    default property alias content: contentItem.data
    property string variant: "default"
    
    implicitWidth: 300
    implicitHeight: contentItem.childrenRect.height + MSpacing.lg * 2
    radius: MRadius.md
    
    color: MColors.glass
    border.width: 1
    border.color: MColors.glassBorder
    
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
        anchors.margins: MSpacing.lg
    }
}

