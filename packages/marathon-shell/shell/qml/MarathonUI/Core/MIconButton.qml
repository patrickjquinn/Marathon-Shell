import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: root
    
    property alias icon: root.iconName
    property string iconName: ""
    property var size: Constants.touchTargetMedium
    property bool disabled: false
    property string variant: "ghost"
    property string shape: "square"
    
    signal clicked()
    
    function getSize() {
        if (typeof size === "number") return size
        if (size === "small") return Constants.touchTargetSmall
        if (size === "large") return Constants.touchTargetLarge
        return Constants.touchTargetMedium
    }
    
    width: getSize()
    height: width
    radius: shape === "circular" ? width / 2 : Constants.borderRadiusSharp
    
    color: {
        if (disabled) return "transparent"
        if (mouseArea.pressed) {
            if (variant === "primary" || variant === "solid") return MColors.accentHover
            return MColors.glass
        }
        if (variant === "primary" || variant === "solid") return MColors.accent
        if (variant === "secondary") return MColors.surface
        return "transparent"
    }
    
    border.width: variant === "primary" ? Constants.borderWidthMedium : Constants.borderWidthThin
    border.color: variant === "primary" ? MColors.accentDark : MColors.borderOuter
    antialiasing: shape === "circular" ? true : Constants.enableAntialiasing
    
    Behavior on color { 
        enabled: Constants.enableAnimations
        ColorAnimation { duration: Constants.animationFast } 
    }
    
    // Inner border for depth (shell pattern)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Constants.borderRadiusSharp
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MColors.borderInner
        antialiasing: Constants.enableAntialiasing
    }
    
    function getIconSize() {
        if (typeof root.size === "number") {
            return Math.max(20, root.size * 0.5)
        }
        if (root.size === "small") return 20
        if (root.size === "large") return 32
        return 24
    }
    
    Image {
        source: iconName !== "" ? "qrc:/images/icons/lucide/" + iconName + ".svg" : ""
        width: getIconSize()
        height: width
        fillMode: Image.PreserveAspectFit
        anchors.centerIn: parent
        smooth: true
        antialiasing: true
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        onClicked: root.clicked()
    }
}

