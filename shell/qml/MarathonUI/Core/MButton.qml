import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Effects
import MarathonUI.Feedback

Rectangle {
    id: root
    
    property string text: ""
    property string variant: "primary"    // primary, secondary, tertiary, ghost, danger, success
    property string size: "medium"        // small, medium, large
    property bool disabled: false
    property string iconName: ""
    property bool iconLeft: true
    property bool fullWidth: false
    property string state: "default"      // default, loading, success, error
    
    signal clicked()
    signal pressed()
    signal released()
    
    implicitWidth: fullWidth ? parent.width : Math.max(minWidth, contentRow.width + horizontalPadding * 2)
    implicitHeight: {
        if (size === "small") return Constants.touchTargetSmall
        if (size === "large") return Constants.touchTargetLarge
        return Constants.touchTargetMedium
    }
    
    readonly property int minWidth: 100
    readonly property int horizontalPadding: {
        if (size === "small") return Constants.spacingMedium
        if (size === "large") return Constants.spacingXLarge
        return Constants.spacingLarge
    }
    
    radius: Constants.borderRadiusSharp
    scale: mouseArea.pressed ? 0.98 : 1.0
    
    color: {
        if (disabled) return MColors.surface0
        if (mouseArea.pressed) {
            if (variant === "primary") return MColors.accentPressed
            if (variant === "secondary") return MColors.glass
            if (variant === "tertiary") return MColors.surface1
            if (variant === "ghost") return MColors.hover
            if (variant === "danger") return MColors.errorDim
            if (variant === "success") return MColors.successDim
            return MColors.surface
        }
        if (variant === "primary") return MColors.accent
        if (variant === "secondary") return MColors.glass
        if (variant === "tertiary") return "transparent"
        if (variant === "ghost") return "transparent"
        if (variant === "danger") return MColors.error
        if (variant === "success") return MColors.success
        return MColors.glass
    }
    
    border.width: Constants.borderWidthThin
    border.color: {
        if (variant === "primary") return MColors.accentBright
        if (variant === "secondary") return MColors.glassBorder
        if (variant === "tertiary") return MColors.border
        if (variant === "ghost") return "transparent"
        if (variant === "danger") return MColors.errorBright
        if (variant === "success") return MColors.successBright
        return MColors.borderOuter
    }
    
    antialiasing: Constants.enableAntialiasing
    
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
        radius: Constants.borderRadiusSharp
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: variant === "primary" ? MColors.borderHighlight : MColors.borderInner
        antialiasing: Constants.enableAntialiasing
        visible: variant !== "ghost" && variant !== "tertiary"
        
        Behavior on border.color {
            enabled: Constants.enableAnimations
            ColorAnimation { duration: MMotion.quick }
        }
    }
    
    // Ripple effect
    MRipple {
        id: rippleEffect
        rippleColor: variant === "primary" ? Qt.rgba(1, 1, 1, 0.2) : MColors.ripple
    }
    
    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Constants.spacingSmall
        layoutDirection: iconLeft ? Qt.LeftToRight : Qt.RightToLeft
        opacity: root.state === "loading" ? 0 : 1
        
        Behavior on opacity {
            enabled: Constants.enableAnimations
            NumberAnimation { duration: MMotion.quick }
        }
        
        Icon {
            visible: iconName !== "" && root.state === "default"
            name: iconName
            size: root.size === "small" ? Constants.iconSizeSmall : (root.size === "large" ? Constants.iconSizeLarge : Constants.iconSizeMedium)
            color: disabled ? MColors.textDisabled : (variant === "primary" ? MColors.textOnAccent : MColors.text)
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Text {
            text: root.text
            color: {
                if (disabled) return MColors.textDisabled
                if (variant === "primary") return MColors.textOnAccent
                return MColors.text
            }
            font.pixelSize: root.size === "small" ? Constants.fontSizeSmall : (root.size === "large" ? Constants.fontSizeLarge : Constants.fontSizeMedium)
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    // Loading spinner
    MActivityIndicator {
        anchors.centerIn: parent
        size: root.size === "small" ? 20 : (root.size === "large" ? 32 : 24)
        visible: root.state === "loading"
        color: variant === "primary" ? MColors.textOnAccent : MColors.accent
    }
    
    // Success icon
    Icon {
        anchors.centerIn: parent
        name: "check"
        size: root.size === "small" ? Constants.iconSizeSmall : (root.size === "large" ? Constants.iconSizeLarge : Constants.iconSizeMedium)
        color: variant === "primary" ? MColors.textOnAccent : MColors.success
        visible: root.state === "success"
        scale: root.state === "success" ? 1 : 0
        
        Behavior on scale {
            enabled: Constants.enableAnimations
            SpringAnimation { 
                spring: MMotion.springLight
                damping: MMotion.dampingLight
                epsilon: MMotion.epsilon
            }
        }
    }
    
    // Error icon
    Icon {
        anchors.centerIn: parent
        name: "x"
        size: root.size === "small" ? Constants.iconSizeSmall : (root.size === "large" ? Constants.iconSizeLarge : Constants.iconSizeMedium)
        color: variant === "primary" ? MColors.textOnAccent : MColors.error
        visible: root.state === "error"
        scale: root.state === "error" ? 1 : 0
        
        Behavior on scale {
            enabled: Constants.enableAnimations
            SpringAnimation { 
                spring: MMotion.springLight
                damping: MMotion.dampingLight
                epsilon: MMotion.epsilon
            }
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !disabled && root.state === "default"
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        
        onPressed: function(mouse) {
            rippleEffect.trigger(Qt.point(mouse.x, mouse.y))
            HapticService.light()
            root.pressed()
        }
        onReleased: root.released()
        onClicked: root.clicked()
    }
}

