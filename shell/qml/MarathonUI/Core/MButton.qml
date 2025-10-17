import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property string text: ""
    property string variant: "primary"
    property string size: "medium"
    property bool disabled: false
    property string iconName: ""
    property bool iconLeft: true
    property bool fullWidth: false
    
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
    
    color: {
        if (disabled) return MColors.surfaceDark
        if (mouseArea.pressed) {
            if (variant === "primary") return MColors.accentHover
            if (variant === "secondary") return MColors.surface
            if (variant === "danger") return Qt.rgba(204/255, 0, 0, 0.8)
            return MColors.surface
        }
        if (variant === "primary") return MColors.accent
        if (variant === "secondary") return MColors.glass
        if (variant === "danger") return MColors.error
        return MColors.glass
    }
    
    border.width: Constants.borderWidthThin
    border.color: {
        if (variant === "primary") return MColors.accentBright
        if (variant === "secondary") return MColors.borderOuter
        if (variant === "danger") return MColors.error
        return MColors.borderOuter
    }
    
    antialiasing: Constants.enableAntialiasing
    
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
    
    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Constants.spacingSmall
        layoutDirection: iconLeft ? Qt.LeftToRight : Qt.RightToLeft
        
        Image {
            visible: iconName !== ""
            source: iconName !== "" ? "qrc:/images/icons/lucide/" + iconName + ".svg" : ""
            width: root.size === "small" ? Constants.iconSizeSmall : (root.size === "large" ? Constants.iconSizeLarge : Constants.iconSizeMedium)
            height: width
            fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
            smooth: true
            antialiasing: Constants.enableAntialiasing
        }
        
        Text {
            text: root.text
            color: disabled ? MColors.textDisabled : MColors.text
            font.pixelSize: root.size === "small" ? Constants.fontSizeSmall : (root.size === "large" ? Constants.fontSizeLarge : Constants.fontSizeMedium)
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        
        onPressed: root.pressed()
        onReleased: root.released()
        onClicked: root.clicked()
    }
    
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: MColors.text
        opacity: mouseArea.pressed ? 0.1 : 0
        z: 100
        
        Behavior on opacity {
            enabled: Constants.enableAnimations
            NumberAnimation { duration: Constants.animationFast }
        }
    }
}

