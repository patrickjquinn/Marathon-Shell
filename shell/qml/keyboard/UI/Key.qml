import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

Rectangle {
    id: key

    property string text: ""
    property string displayText: text
    property string alternateText: ""
    property var alternateChars: []
    property bool isSpecial: false
    property string iconName: ""
    property int keyCode: Qt.Key_unknown
    property alias fontFamily: keyText.font.family
    property bool pressed: false
    property bool highlighted: false
    property bool showingAlternates: false
    property real cachedTextWidth: 0
    property real cachedTextHeight: 0

    signal clicked
    signal pressAndHold
    signal released
    signal alternateSelected(string character)

    width: Math.round(60 * Constants.scaleFactor)
    height: Math.round(45 * Constants.scaleFactor)
    radius: Constants.borderRadiusSharp
    color: {
        if (pressed)
            return MColors.accentBright;

        if (isSpecial)
            return "#1a1a1a";

        return "#000000";
    }
    border.width: 0
    antialiasing: Constants.enableAntialiasing
    layer.enabled: true
    layer.smooth: true
    scale: pressed ? 0.95 : 1

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(2 * Constants.scaleFactor)
        color: "#0a0a0a"
        radius: 0
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.round(2 * Constants.scaleFactor)
        color: "#0a0a0a"
        radius: 0
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(2 * Constants.scaleFactor)
        radius: parent.radius > 0 ? parent.radius - 2 : 0
        color: "transparent"
        border.width: Math.round(1 * Constants.scaleFactor)
        border.color: key.pressed ? MColors.marathonTealHoverGradient : "#555555"
        antialiasing: parent.antialiasing
    }

    Item {
        anchors.centerIn: parent
        width: parent.width - Math.round(12 * Constants.scaleFactor)
        height: parent.height - Math.round(8 * Constants.scaleFactor)

        Icon {
            visible: key.iconName !== ""
            name: key.iconName
            size: Math.round(20 * Constants.scaleFactor)
            color: key.pressed ? MColors.bb10Black : MColors.textPrimary
            anchors.centerIn: parent
            opacity: key.pressed ? 1 : 0.9
        }

        Text {
            id: keyText

            visible: key.iconName === ""
            text: key.displayText
            color: key.pressed ? MColors.bb10Black : MColors.textPrimary
            font.pixelSize: key.isSpecial ? Math.round(14 * Constants.scaleFactor) : Math.round(18 * Constants.scaleFactor)
            font.weight: key.isSpecial ? Font.Medium : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.centerIn: parent
            opacity: key.pressed ? 1 : 0.9
        }

        Text {
            visible: key.alternateText !== "" && !key.pressed
            text: key.alternateText
            color: MColors.textSecondary
            font.pixelSize: Math.round(10 * Constants.scaleFactor)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Math.round(2 * Constants.scaleFactor)
            opacity: 0.6
        }
    }

    Rectangle {
        id: preview

        visible: key.pressed && !key.isSpecial && !key.showingAlternates
        width: Math.round(70 * Constants.scaleFactor)
        height: Math.round(80 * Constants.scaleFactor)
        x: (parent.width - width) / 2
        y: -height - Math.round(10 * Constants.scaleFactor)
        z: 1000
        radius: Constants.borderRadiusMedium
        color: MColors.elevated
        border.width: Constants.borderWidthMedium
        border.color: MColors.border
        antialiasing: true
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.highlightMedium
            antialiasing: true
        }

        Text {
            text: key.displayText
            color: MColors.textPrimary
            font.pixelSize: Math.round(32 * Constants.scaleFactor)
            font.weight: Font.Normal
            anchors.centerIn: parent
        }

        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 0.4
            shadowOpacity: 0.6
        }
    }

    Loader {
        id: alternatePopup

        property real popupWidth: Math.round((60 * key.alternateChars.length + 4 * (key.alternateChars.length - 1)) * Constants.scaleFactor)
        property real keyGlobalX: key.mapToItem(null, 0, 0).x
        property real screenWidth: Constants.screenWidth

        active: key.showingAlternates && key.alternateChars.length > 0
        z: 2000
        x: {
            var centerX = (key.width - popupWidth) / 2;
            var leftEdge = keyGlobalX + centerX;
            var rightEdge = leftEdge + popupWidth;
            if (leftEdge < 0)
                return -keyGlobalX;
            else if (rightEdge > screenWidth)
                return screenWidth - keyGlobalX - popupWidth;
            else
                return centerX;
        }
        anchors.bottom: parent.top
        anchors.bottomMargin: Math.round(8 * Constants.scaleFactor)

        sourceComponent: Rectangle {
            width: alternatePopup.popupWidth
            height: Math.round(50 * Constants.scaleFactor)
            radius: Constants.borderRadiusMedium
            color: MColors.elevated
            border.width: Constants.borderWidthMedium
            border.color: MColors.accentBright
            antialiasing: true
            layer.enabled: true

            Row {
                anchors.centerIn: parent
                spacing: Math.round(4 * Constants.scaleFactor)

                Repeater {
                    model: key.alternateChars

                    Rectangle {
                        width: Math.round(50 * Constants.scaleFactor)
                        height: Math.round(40 * Constants.scaleFactor)
                        radius: Constants.borderRadiusSmall
                        color: altMouseArea.pressed ? MColors.accentBright : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: MColors.textPrimary
                            font.pixelSize: Math.round(20 * Constants.scaleFactor)
                        }

                        MouseArea {
                            id: altMouseArea

                            anchors.fill: parent
                            onClicked: {
                                HapticManager.light();
                                key.alternateSelected(modelData);
                                key.showingAlternates = false;
                            }
                        }
                    }
                }
            }

            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowBlur: 0.4
                shadowOpacity: 0.6
            }
        }
    }

    MouseArea {
        id: mouseArea

        property bool longPressTriggered: false

        anchors.fill: parent
        onPressed: function (mouse) {
            key.pressed = true;
            longPressTriggered = false;
            HapticManager.light();
            if (key.alternateChars.length > 0)
                longPressTimer.restart();

            mouse.accepted = true;
        }
        onReleased: function (mouse) {
            longPressTimer.stop();
            key.pressed = false;
            if (!longPressTriggered && containsMouse) {
                if (!key.showingAlternates)
                    key.clicked();
            }
            key.showingAlternates = false;
            key.released();
            mouse.accepted = true;
        }
        onCanceled: {
            longPressTimer.stop();
            key.pressed = false;
            key.showingAlternates = false;
        }
    }

    Timer {
        id: longPressTimer

        interval: 500
        repeat: false
        onTriggered: {
            if (key.alternateChars.length > 0) {
                HapticManager.medium();
                key.showingAlternates = true;
                mouseArea.longPressTriggered = true;
                key.pressAndHold();
            }
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 50
            easing.type: Easing.Linear
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 50
            easing.type: Easing.Linear
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 50
            easing.type: Easing.OutCubic
        }
    }
}
