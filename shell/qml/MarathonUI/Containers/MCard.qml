import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: root
    
    default property alias content: contentItem.data
    property string variant: "default"
    property int elevation: 1
    property int elevationHover: elevation + 1
    property int elevationPressed: elevation - 1
    property bool pressed: false
    property bool interactive: false
    property bool hovered: false
    
    signal clicked()
    
    implicitWidth: 300
    implicitHeight: contentItem.childrenRect.height + Constants.spacingLarge * 2
    radius: Constants.borderRadiusSharp
    scale: pressed ? 0.98 : 1.0
    
    readonly property int currentElevation: pressed ? Math.max(0, elevationPressed) : (hovered ? elevationHover : elevation)
    
    color: MElevation.getSurface(currentElevation)
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(currentElevation)
    antialiasing: Constants.enableAntialiasing
    
    Behavior on color {
        enabled: Constants.enableAnimations
        ColorAnimation { duration: MMotion.quick }
    }
    
    Behavior on scale {
        enabled: Constants.enableAnimations && interactive
        SpringAnimation { 
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilon
        }
    }
    
    Rectangle {
        id: innerBorder
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin
        radius: root.radius > 0 ? root.radius - Constants.borderWidthThin : 0
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderInner(currentElevation)
        antialiasing: Constants.enableAntialiasing
        
        Behavior on border.color {
            enabled: Constants.enableAnimations
            ColorAnimation { duration: MMotion.quick }
        }
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: Constants.spacingLarge
    }
    
    MouseArea {
        anchors.fill: parent
        enabled: interactive
        hoverEnabled: interactive
        cursorShape: interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: if (interactive) { root.hovered = true; HapticService.light() }
        onExited: root.hovered = false
        onPressed: if (interactive) { root.pressed = true }
        onReleased: root.pressed = false
        onCanceled: root.pressed = false
        onClicked: if (interactive) { root.clicked(); HapticService.medium() }
    }
}

