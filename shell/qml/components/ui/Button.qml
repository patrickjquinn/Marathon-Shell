import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

// DEPRECATED: Use MarathonUI.Core.MButton instead
// This component is kept for backward compatibility only

Rectangle {
    id: button

    Component.onCompleted: {
        console.warn("DEPRECATED: components/ui/Button is deprecated. Use MarathonUI.Core.MButton instead.");
    }

    property string text: ""
    property string variant: "primary"
    property bool disabled: false
    property int iconSize: 20
    property string iconName: ""

    signal clicked
    signal pressed
    signal released

    width: Math.max(Math.round(120 * Constants.scaleFactor), buttonText.width + Math.round(32 * Constants.scaleFactor))
    height: Constants.touchTargetMedium  // BB10: 70px minimum
    radius: Constants.borderRadiusSmall

    color: {
        if (disabled)
            return "#333333";
        if (mouseArea.pressed) {
            return variant === "primary" ? "#004d4d" : variant === "secondary" ? "#2A2A2A" : variant === "danger" ? "#AA0000" : "#2A2A2A";
        }
        return variant === "primary" ? "#006666" : variant === "secondary" ? "#1A1A1A" : variant === "danger" ? "#CC0000" : "#1A1A1A";
    }

    border.width: variant === "secondary" ? 1 : 0
    border.color: "#006666"

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 100
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: Constants.spacingSmall

        Image {
            visible: iconName !== ""
            source: iconName !== "" ? "qrc:/images/icons/lucide/" + iconName + ".svg" : ""
            width: iconSize
            height: iconSize
            fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: buttonText
            text: button.text
            color: disabled ? "#666666" : "#FFFFFF"
            font.pixelSize: Constants.fontSizeMedium
            font.weight: Font.Medium
            font.family: MTypography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !disabled

        onPressed: {
            button.scale = 0.95;
            button.pressed();
        }

        onReleased: {
            button.scale = 1.0;
            button.released();
        }

        onClicked: {
            button.clicked();
        }
    }

    // BB10 Highlight behavior (page 111)
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "#FFFFFF"
        opacity: mouseArea.pressed ? 0.2 : 0
        z: 100

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }
}
