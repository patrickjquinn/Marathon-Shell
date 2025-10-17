import QtQuick
import MarathonOS.Shell

Rectangle {
    id: root
    
    property alias content: contentItem.children
    
    color: MColors.surfaceDark
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: Qt.rgba(0, 0, 0, 1.0)
    antialiasing: Constants.enableAntialiasing
    
    Rectangle {
        id: innerHighlight
        anchors.fill: parent
        anchors.topMargin: 0
        anchors.leftMargin: 0
        anchors.rightMargin: Constants.borderWidthThin
        anchors.bottomMargin: Constants.borderWidthThin
        radius: parent.radius
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: Qt.rgba(1, 1, 1, 0.03)
        antialiasing: Constants.enableAntialiasing
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin * 2
    }
}

