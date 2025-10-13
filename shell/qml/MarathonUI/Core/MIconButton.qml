import QtQuick
import "../Theme"

Rectangle {
    id: root
    
    property string iconName: ""
    property string size: "medium"
    property bool disabled: false
    property string variant: "ghost"
    
    signal clicked()
    
    width: {
        if (size === "small") return 40
        if (size === "large") return 60
        return 48
    }
    height: width
    radius: MRadius.md
    
    color: {
        if (disabled) return "transparent"
        if (mouseArea.pressed) {
            if (variant === "solid") return MColors.accentHover
            return MColors.glass
        }
        if (variant === "solid") return MColors.accent
        return "transparent"
    }
    
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    
    scale: mouseArea.pressed ? 0.95 : 1.0
    
    Image {
        source: iconName !== "" ? "qrc:/images/icons/lucide/" + iconName + ".svg" : ""
        width: {
            if (root.size === "small") return 20
            if (root.size === "large") return 32
            return 24
        }
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

