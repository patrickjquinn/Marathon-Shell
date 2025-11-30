// Marathon Virtual Keyboard - Key Component
// Optimized for zero-latency input
import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: key

    // Key properties
    property string text: ""
    property string displayText: text
    property string alternateText: ""  // For long-press (e.g., "1" shows "!")
    property var alternateChars: []    // Array of alternate characters
    property bool isSpecial: false     // Shift, Enter, Backspace
    property string iconName: ""       // Lucide icon for special keys
    property int keyCode: Qt.Key_unknown

    property alias fontFamily: keyText.font.family

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
    width: Math.round(60 * Constants.scaleFactor)
    height: Math.round(45 * Constants.scaleFactor)
    radius: Constants.borderRadiusSharp
    color: {
        if (pressed)
            return MColors.accentBright;
        if (isSpecial)
            return "#1a1a1a";  // Dark grey for special keys
        return "#000000";  // Pure black for letter keys
    }

    // Physical button styling - DARK borders, partial (bottom/right only)
    border.width: 0  // No full border
    antialiasing: Constants.enableAntialiasing

    // Bottom border (darker, creates depth)
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(2 * Constants.scaleFactor)
        color: "#0a0a0a"  // Very dark, almost black
        radius: 0
    }

    // Right border (darker, creates depth)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.round(2 * Constants.scaleFactor)
        color: "#0a0a0a"  // Very dark, almost black
        radius: 0
    }

    // PERFORMANCE: Enable layer for GPU-accelerated scale/transform animations
    // This moves rendering to GPU, preventing CPU-bound repaints on every frame
    layer.enabled: true
    layer.smooth: true

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

    // PERFORMANCE: Use NumberAnimation instead of SpringAnimation for scale
    // SpringAnimation is expensive - only use for special effects
    Behavior on scale {
        NumberAnimation {
            duration: 50
            easing.type: Easing.OutCubic
        }
    }

    scale: pressed ? 0.95 : 1.0

    // Inner border for physical button depth (shine effect)
    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(2 * Constants.scaleFactor)
        radius: parent.radius > 0 ? parent.radius - 2 : 0
        color: "transparent"
        border.width: Math.round(1 * Constants.scaleFactor)
        border.color: key.pressed ? MColors.marathonTealHoverGradient : "#555555"  // Lighter grey for depth
        antialiasing: parent.antialiasing
    }

    // Content: Either icon or text
    Item {
        anchors.centerIn: parent
        width: parent.width - Math.round(12 * Constants.scaleFactor)
        height: parent.height - Math.round(8 * Constants.scaleFactor)

        // Icon for special keys
        Icon {
            visible: key.iconName !== ""
            name: key.iconName
            size: Math.round(20 * Constants.scaleFactor)
            color: key.pressed ? MColors.bb10Black : MColors.textPrimary  // Dark text on bright teal, matching primary button style
            anchors.centerIn: parent
            opacity: key.pressed ? 1.0 : 0.9
        }

        // Text for regular keys
        Text {
            id: keyText
            visible: key.iconName === ""
            text: key.displayText
            color: key.pressed ? MColors.bb10Black : MColors.textPrimary  // Dark text on bright teal, matching primary button style
            font.pixelSize: key.isSpecial ? Math.round(14 * Constants.scaleFactor) : Math.round(18 * Constants.scaleFactor)
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
            color: MColors.textSecondary
            font.pixelSize: Math.round(10 * Constants.scaleFactor)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Math.round(2 * Constants.scaleFactor)
            opacity: 0.6
        }
    }

    // Character preview popup (BB10 style) - HIDDEN when showing alternates
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

        // Inner border
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.highlightMedium
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
            color: MColors.textPrimary
            font.pixelSize: Math.round(32 * Constants.scaleFactor)
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
        property real popupWidth: Math.round((60 * key.alternateChars.length + 4 * (key.alternateChars.length - 1)) * Constants.scaleFactor)
        property real keyGlobalX: key.mapToItem(null, 0, 0).x
        property real screenWidth: Constants.screenWidth

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
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowBlur: 0.4
                shadowOpacity: 0.6
            }

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
                                HapticService.light();
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
            HapticService.light();

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
                HapticService.medium();
                key.showingAlternates = true;
                mouseArea.longPressTriggered = true;
                key.pressAndHold();
            }
        }
    }
}
