import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: card
    color: MColors.surface
    radius: Constants.borderRadiusSharp
    
    property alias content: contentItem.children
    property int elevation: 1
    property bool hoverable: false
    
    border.width: Constants.borderWidthThin
    border.color: MColors.borderOuter
    antialiasing: Constants.enableAntialiasing
    
    Behavior on border.color {
        ColorAnimation { duration: 150 }
    }
    
    // Inner border for depth (MElevation technique)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Constants.borderRadiusSharp
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MColors.borderInner
        antialiasing: Constants.enableAntialiasing
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: 0
    }
}

