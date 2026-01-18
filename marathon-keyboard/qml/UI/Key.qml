import QtQuick
import QtQuick.Effects
import MarathonUI.Core 2.0

Rectangle {
    id: key

    property var keyboard: null
    property real scaleFactor: keyboard ? keyboard.scaleFactor : 1.0

    property string text: ""
    property string displayText: text
    property string alternateText: ""
    property var alternateChars: []
    property bool isSpecial: false
    property string iconName: ""
    property int keyCode: Qt.Key_unknown

    property bool pressed: false
    property bool highlighted: false
    property bool showingAlternates: false

    property real cachedTextWidth: 0
    property real cachedTextHeight: 0

    signal clicked
    signal pressAndHold
    signal released
    signal alternateSelected(string character)

    width: Math.round(60 * scaleFactor)
    height: Math.round(45 * scaleFactor)
    radius: keyboard ? keyboard.borderRadius : 4
    color: {
        if (pressed)
            return keyboard ? keyboard.keyPressedColor : "#007ACC";
        if (isSpecial)
            return "#1a1a1a";
        return keyboard ? keyboard.keyBackgroundColor : "#000000";
    }

    border.width: 0
    antialiasing: true

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(2 * scaleFactor)
        color: "#0a0a0a"
        radius: 0
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.round(2 * scaleFactor)
        color: "#0a0a0a"
        radius: 0
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
            duration: 80
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Behavior on y {
        NumberAnimation {
            duration: 80
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    scale: pressed ? 1.05 : 1.0
    y: pressed ? -Math.round(3 * scaleFactor) : 0
    z: pressed ? 100 : 1

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(2 * scaleFactor)
        radius: parent.radius > 0 ? parent.radius - 2 : 0
        color: "transparent"
        border.width: Math.round(1 * scaleFactor)
        border.color: key.pressed ? (keyboard ? keyboard.keyPressedColor : "#007ACC") : "#555555"
        antialiasing: parent.antialiasing
    }

    Item {
        anchors.centerIn: parent
        width: parent.width - Math.round(12 * scaleFactor)
        height: parent.height - Math.round(8 * scaleFactor)

        Icon {
            visible: key.iconName !== ""
            name: key.iconName
            size: Math.round(20 * scaleFactor)
            color: keyboard ? keyboard.textColor : "#FFFFFF"
            anchors.centerIn: parent
            opacity: key.pressed ? 1.0 : 0.9
        }

        Text {
            visible: key.iconName === ""
            text: key.displayText
            color: keyboard ? keyboard.textColor : "#FFFFFF"
            font.pixelSize: key.isSpecial ? Math.round(14 * scaleFactor) : Math.round(18 * scaleFactor)
            font.weight: key.isSpecial ? Font.Medium : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.centerIn: parent
            opacity: key.pressed ? 1.0 : 0.9
        }

        Text {
            visible: key.alternateText !== "" && !key.pressed
            text: key.alternateText
            color: keyboard ? keyboard.textSecondaryColor : "#A0A0A0"
            font.pixelSize: Math.round(10 * scaleFactor)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Math.round(2 * scaleFactor)
            opacity: 0.6
        }
    }

    Rectangle {
        id: preview
        visible: key.pressed && !key.isSpecial && !key.showingAlternates
        width: Math.round(70 * scaleFactor)
        height: Math.round(80 * scaleFactor)
        x: (parent.width - width) / 2
        y: -height - Math.round(10 * scaleFactor)
        z: 1000

        radius: keyboard ? keyboard.borderRadius : 4
        color: keyboard ? keyboard.keyBackgroundColor : "#2D2D30"
        border.width: Math.round(1 * scaleFactor)
        border.color: keyboard ? keyboard.borderColor : "#3E3E42"
        antialiasing: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: Math.round(1 * scaleFactor)
            border.color: keyboard ? keyboard.keyPressedColor : "#00D4AA"
            antialiasing: true
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 0.4
            shadowOpacity: 0.6
        }

        Text {
            text: key.displayText
            color: keyboard ? keyboard.textColor : "#FFFFFF"
            font.pixelSize: Math.round(32 * scaleFactor)
            font.weight: Font.Normal
            anchors.centerIn: parent
        }
    }

    Loader {
        id: alternatePopup
        active: key.showingAlternates && key.alternateChars.length > 0
        z: 2000

        property real popupWidth: Math.round((60 * key.alternateChars.length + 4 * (key.alternateChars.length - 1)) * scaleFactor)
        property real keyGlobalX: key.mapToItem(null, 0, 0).x
        property real screenWidth: keyboard ? keyboard.width : 540

        x: {
            var centerX = (key.width - popupWidth) / 2;
            var leftEdge = keyGlobalX + centerX;
            var rightEdge = leftEdge + popupWidth;

            if (leftEdge < 0) {
                return -keyGlobalX;
            } else if (rightEdge > screenWidth) {
                return screenWidth - keyGlobalX - popupWidth;
            } else {
                return centerX;
            }
        }

        anchors.bottom: parent.top
        anchors.bottomMargin: Math.round(8 * scaleFactor)

        sourceComponent: Rectangle {
            width: alternatePopup.popupWidth
            height: Math.round(50 * scaleFactor)
            radius: keyboard ? keyboard.borderRadius : 4
            color: keyboard ? keyboard.keyBackgroundColor : "#2D2D30"
            border.width: Math.round(2 * scaleFactor)
            border.color: keyboard ? keyboard.keyPressedColor : "#00D4AA"
            antialiasing: true

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowBlur: 0.4
                shadowOpacity: 0.6
            }

            Row {
                anchors.centerIn: parent
                spacing: Math.round(4 * scaleFactor)

                Repeater {
                    model: key.alternateChars

                    Rectangle {
                        width: Math.round(50 * scaleFactor)
                        height: Math.round(40 * scaleFactor)
                        radius: Math.round(3 * scaleFactor)
                        color: altMouseArea.pressed ? (keyboard ? keyboard.keyPressedColor : "#00D4AA") : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: keyboard ? keyboard.textColor : "#FFFFFF"
                            font.pixelSize: Math.round(20 * scaleFactor)
                        }

                        MouseArea {
                            id: altMouseArea
                            anchors.fill: parent
                            onClicked: {
                                if (keyboard)
                                    keyboard.hapticRequested("light");
                                key.alternateSelected(modelData);
                                key.showingAlternates = false;
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent

        property bool longPressTriggered: false

        onPressed: function (mouse) {
            key.pressed = true;
            longPressTriggered = false;
            if (keyboard)
                keyboard.hapticRequested("light");

            if (key.alternateChars.length > 0) {
                longPressTimer.restart();
            }

            mouse.accepted = true;
        }

        onReleased: function (mouse) {
            longPressTimer.stop();
            key.pressed = false;

            if (!longPressTriggered && containsMouse) {
                if (!key.showingAlternates) {
                    key.clicked();
                }
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
                if (keyboard)
                    keyboard.hapticRequested("medium");
                key.showingAlternates = true;
                mouseArea.longPressTriggered = true;
                key.pressAndHold();
            }
        }
    }
}
