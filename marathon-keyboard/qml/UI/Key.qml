// Marathon Virtual Keyboard - Key Component
// Optimized for zero-latency input
import QtQuick
import QtQuick.Effects
import MarathonUI.Core 2.0

Rectangle {
    id: key

    // Reference to parent keyboard for theme access
    property var keyboard: null
    property real scaleFactor: keyboard ? keyboard.scaleFactor : 1.0

    // Key properties
    property string text: ""
    property string displayText: text
    property string alternateText: ""  // For long-press (e.g., "1" shows "!")
    property var alternateChars: []    // Array of alternate characters
    property bool isSpecial: false     // Shift, Enter, Backspace
    property string iconName: ""       // Lucide icon for special keys
    property int keyCode: Qt.Key_unknown

    // State
    property bool pressed: false
    property bool highlighted: false
    property bool showingAlternates: false

    // PERFORMANCE: Cache text metrics to avoid re-layout
    property real cachedTextWidth: 0
    property real cachedTextHeight: 0

    // Signals
    signal clicked
    signal pressAndHold
    signal released
    signal alternateSelected(string character)

    // Styling - BlackBerry style: BLACK keys, dark grey special keys
    width: Math.round(60 * scaleFactor)
    height: Math.round(45 * scaleFactor)
    radius: keyboard ? keyboard.borderRadius : 4
    color: {
        if (pressed)
            return keyboard ? keyboard.keyPressedColor : "#007ACC";
        if (isSpecial)
            return "#1a1a1a";  // Dark grey for special keys
        return keyboard ? keyboard.keyBackgroundColor : "#000000";  // Key background
    }

    // Physical button styling - DARK borders, partial (bottom/right only)
    border.width: 0  // No full border
    antialiasing: true

    // Bottom border (darker, creates depth)
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(2 * scaleFactor)
        color: "#0a0a0a"  // Very dark, almost black
        radius: 0
    }

    // Right border (darker, creates depth)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.round(2 * scaleFactor)
        color: "#0a0a0a"  // Very dark, almost black
        radius: 0
    }

    // PERFORMANCE: Use fast color animation instead of general Behavior
    Behavior on color {
        ColorAnimation {
            duration: 50 // Fixed duration for predictability
            easing.type: Easing.Linear // Linear is fastest
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 50
            easing.type: Easing.Linear
        }
    }

    // PERFORMANCE: Use NumberAnimation for scale and translate
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

    // Pop over effect when pressed: scale up slightly and lift
    scale: pressed ? 1.05 : 1.0
    y: pressed ? -Math.round(3 * scaleFactor) : 0
    z: pressed ? 100 : 1

    // Inner border for physical button depth (shine effect)
    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(2 * scaleFactor)
        radius: parent.radius > 0 ? parent.radius - 2 : 0
        color: "transparent"
        border.width: Math.round(1 * scaleFactor)
        border.color: key.pressed ? (keyboard ? keyboard.keyPressedColor : "#007ACC") : "#555555"  // Lighter grey for depth
        antialiasing: parent.antialiasing
    }

    // Content: Either icon or text
    Item {
        anchors.centerIn: parent
        width: parent.width - Math.round(12 * scaleFactor)
        height: parent.height - Math.round(8 * scaleFactor)

        // Icon for special keys
        Icon {
            visible: key.iconName !== ""
            name: key.iconName
            size: Math.round(20 * scaleFactor)
            color: keyboard ? keyboard.textColor : "#FFFFFF"
            anchors.centerIn: parent
            opacity: key.pressed ? 1.0 : 0.9
        }

        // Text for regular keys
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

        // Alternate text (top-right corner for long-press hint)
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

    // Character preview popup (BB10 style) - HIDDEN when showing alternates
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

        // Inner border - Marathon teal highlight
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: Math.round(1 * scaleFactor)
            border.color: keyboard ? keyboard.keyPressedColor : "#00D4AA"  // Marathon teal
            antialiasing: true
        }

        // Shadow effect
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 0.4
            shadowOpacity: 0.6
        }

        // Preview text (larger)
        Text {
            text: key.displayText
            color: keyboard ? keyboard.textColor : "#FFFFFF"
            font.pixelSize: Math.round(32 * scaleFactor)
            font.weight: Font.Normal
            anchors.centerIn: parent
        }
    }

    // Long-press alternate popup - DYNAMIC positioning to prevent off-screen
    Loader {
        id: alternatePopup
        active: key.showingAlternates && key.alternateChars.length > 0
        z: 2000

        // Dynamic positioning based on key location
        property real popupWidth: Math.round((60 * key.alternateChars.length + 4 * (key.alternateChars.length - 1)) * scaleFactor)
        property real keyGlobalX: key.mapToItem(null, 0, 0).x
        property real screenWidth: keyboard ? keyboard.width : 540

        // Center by default, but shift if too close to edge
        x: {
            var centerX = (key.width - popupWidth) / 2;
            var leftEdge = keyGlobalX + centerX;
            var rightEdge = leftEdge + popupWidth;

            if (leftEdge < 0) {
                // Too far left, shift right
                return -keyGlobalX;
            } else if (rightEdge > screenWidth) {
                // Too far right, shift left
                return screenWidth - keyGlobalX - popupWidth;
            } else {
                // Centered is fine
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
            border.color: keyboard ? keyboard.keyPressedColor : "#00D4AA"  // Marathon teal
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

    // Touch handling - OPTIMIZED FOR ZERO LATENCY
    MouseArea {
        id: mouseArea
        anchors.fill: parent

        property bool longPressTriggered: false

        // CRITICAL: onPressed fires IMMEDIATELY (synchronous)
        // This gives instant visual feedback before event propagation
        onPressed: function (mouse) {
            key.pressed = true;  // INSTANT visual change
            longPressTriggered = false;
            if (keyboard)
                keyboard.hapticRequested("light");

            // Start long-press timer if alternates exist
            if (key.alternateChars.length > 0) {
                longPressTimer.restart();
            }

            // Accept event to prevent propagation delay
            mouse.accepted = true;
        }

        onReleased: function (mouse) {
            longPressTimer.stop();
            key.pressed = false;

            if (!longPressTriggered && containsMouse) {
                if (!key.showingAlternates) {
                    // Emit clicked immediately
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

    // Long-press timer
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
