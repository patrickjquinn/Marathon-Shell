import QtQuick
import MarathonOS.Shell

Rectangle {
    id: root
    
    property alias content: contentItem.children
    
    color: MColors.surface
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: Qt.rgba(1, 1, 1, 0.08)
    antialiasing: Constants.enableAntialiasing
    
    Rectangle {
        id: innerShadow
        anchors.fill: parent
        anchors.topMargin: Constants.borderWidthThin
        anchors.leftMargin: Constants.borderWidthThin
        anchors.rightMargin: 0
        anchors.bottomMargin: 0
        radius: parent.radius
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: Qt.rgba(0, 0, 0, 1.0)
        antialiasing: Constants.enableAntialiasing
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin * 2
    }
}

