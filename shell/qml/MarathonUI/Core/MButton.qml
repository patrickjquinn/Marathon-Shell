import QtQuick
import "../Theme"

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
        if (size === "small") return MSpacing.touchTargetSmall
        if (size === "large") return MSpacing.touchTargetLarge
        return MSpacing.touchTargetMedium
    }
    
    readonly property int minWidth: 100
    readonly property int horizontalPadding: {
        if (size === "small") return MSpacing.md
        if (size === "large") return MSpacing.xl
        return MSpacing.lg
    }
    
    radius: MRadius.md
    
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
    
    border.width: variant === "secondary" ? 1 : 0
    border.color: variant === "secondary" ? MColors.border : "transparent"
    
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    
    scale: mouseArea.pressed ? 0.98 : 1.0
    
    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: MSpacing.sm
        layoutDirection: iconLeft ? Qt.LeftToRight : Qt.RightToLeft
        
        Image {
            visible: iconName !== ""
            source: iconName !== "" ? "qrc:/images/icons/lucide/" + iconName + ".svg" : ""
            width: root.size === "small" ? 16 : (root.size === "large" ? 24 : 20)
            height: width
            fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
            smooth: true
            antialiasing: true
        }
        
        Text {
            text: root.text
            color: disabled ? MColors.textDisabled : MColors.text
            font.pixelSize: root.size === "small" ? MTypography.sizeSmall : (root.size === "large" ? MTypography.sizeLarge : MTypography.sizeBody)
            font.weight: MTypography.weightDemiBold
            font.family: MTypography.fontFamily
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
            NumberAnimation { duration: 150 }
        }
    }
}

