import QtQuick
import MarathonOS.Shell

Rectangle {
    id: root
    
    default property alias content: contentItem.data
    property string variant: "default"
    property int elevation: 1
    property bool pressed: false
    
    implicitWidth: 300
    implicitHeight: contentItem.childrenRect.height + Constants.spacingLarge * 2
    radius: Constants.borderRadiusSharp
    
    color: pressed ? MColors.surface0 : MElevation.getSurface(root.elevation)
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(root.elevation)
    antialiasing: Constants.enableAntialiasing
    
    Behavior on color {
        enabled: Constants.enableAnimations
        ColorAnimation { duration: Constants.animationFast }
    }
    
    Rectangle {
        id: innerBorder
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin
        radius: parent.radius > 0 ? parent.radius - Constants.borderWidthThin : 0
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: root.pressed ? Qt.rgba(1, 1, 1, 0.02) : MElevation.getBorderInner(root.elevation)
        antialiasing: Constants.enableAntialiasing
        
        Behavior on border.color {
            enabled: Constants.enableAnimations
            ColorAnimation { duration: Constants.animationFast }
        }
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Constants.spacingLarge
    }
}

