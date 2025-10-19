import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Effects

Rectangle {
    id: root
    
    property alias icon: root.iconName
    property string iconName: ""
    property var size: Constants.touchTargetMedium
    property bool disabled: false
    property string variant: "ghost"      // ghost, primary, secondary, solid
    property string shape: "square"       // square, circular
    property color iconColor: variant === "primary" || variant === "solid" ? MColors.textOnAccent : MColors.text
    
    signal clicked()
    
    function getSize() {
        if (typeof root.size === "number") return root.size
        if (root.size === "small") return Constants.touchTargetSmall
        if (root.size === "large") return Constants.touchTargetLarge
        return Constants.touchTargetMedium
    }
    
    width: getSize()
    height: width
    radius: root.shape === "circular" ? width / 2 : Constants.borderRadiusSharp
    scale: mouseArea.pressed ? 0.95 : 1.0
    
    color: {
        if (root.disabled) return "transparent"
        if (mouseArea.pressed) {
            if (root.variant === "primary" || root.variant === "solid") return MColors.accentPressed
            if (root.variant === "secondary") return MColors.glass
            return MColors.hover
        }
        if (root.variant === "primary" || root.variant === "solid") return MColors.accent
        if (root.variant === "secondary") return MColors.glass
        return "transparent"
    }
    
    border.width: root.variant === "primary" ? Constants.borderWidthMedium : Constants.borderWidthThin
    border.color: {
        if (root.variant === "primary") return MColors.accentBright
        if (root.variant === "secondary") return MColors.glassBorder
        return "transparent"
    }
    antialiasing: root.shape === "circular" ? true : Constants.enableAntialiasing
    
    Behavior on color { 
        enabled: Constants.enableAnimations
        ColorAnimation { duration: MMotion.quick } 
    }
    
    Behavior on scale {
        enabled: Constants.enableAnimations
        SpringAnimation { 
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilon
        }
    }
    
    // Inner border for depth
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: root.variant === "primary" ? MColors.borderHighlight : MColors.borderInner
        antialiasing: parent.antialiasing
        visible: root.variant === "primary" || root.variant === "secondary" || root.variant === "solid"
        
        Behavior on border.color {
            enabled: Constants.enableAnimations
            ColorAnimation { duration: MMotion.quick }
        }
    }
    
    // Ripple effect
    MRipple {
        id: rippleEffect
        rippleColor: root.variant === "primary" || root.variant === "solid" ? Qt.rgba(1, 1, 1, 0.2) : MColors.ripple
    }
    
    function getIconSize() {
        if (typeof root.size === "number") {
            return Math.max(20, root.size * 0.5)
        }
        if (root.size === "small") return 20
        if (root.size === "large") return 32
        return 24
    }
    
    Icon {
        name: root.iconName
        size: getIconSize()
        color: root.disabled ? MColors.textDisabled : root.iconColor
        anchors.centerIn: parent
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !root.disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        onPressed: function(mouse) {
            rippleEffect.trigger(Qt.point(mouse.x, mouse.y))
            HapticService.light()
        }
        onClicked: root.clicked()
    }
}

