import QtQuick
import MarathonOS.Shell

Rectangle {
    id: root
    
    property int elevation: 1
    property alias content: contentItem.children
    
    color: MElevation.getSurface(root.elevation)
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(root.elevation)
    antialiasing: Constants.enableAntialiasing
    
    Rectangle {
        id: innerBorder
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin
        radius: parent.radius > 0 ? parent.radius - Constants.borderWidthThin : 0
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderInner(root.elevation)
        antialiasing: Constants.enableAntialiasing
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin * 2
    }
}

