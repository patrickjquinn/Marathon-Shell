// Marathon Virtual Keyboard - Main Container
// BlackBerry 10-inspired keyboard with Marathon design
// OPTIMIZED FOR ZERO LATENCY INPUT
import QtQuick
import MarathonKeyboard.UI 1.0
import MarathonKeyboard.Layouts 1.0

Rectangle {
    id: keyboard

    // Abstraction properties - set by parent/shell
    property real scaleFactor: 1.0

    // Theme properties - passed from shell
    property color backgroundColor: "#1E1E1E"
    property color keyBackgroundColor: "#2D2D30"
    property color keyPressedColor: "#007ACC"
    property color textColor: "#FFFFFF"
    property color textSecondaryColor: "#A0A0A0"
    property color borderColor: "#3E3E42"
    property real borderRadius: 4
    property real keySpacing: 4

    // Signals for abstraction
    signal logMessage(string category, string message)
    signal hapticRequested(string intensity)

    // State
    property bool active: false
    property string currentLayout: "qwerty"
    property bool shifted: false
    property bool capsLock: false
    property bool predictionEnabled: true
}
