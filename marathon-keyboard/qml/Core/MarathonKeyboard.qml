import QtQuick
import MarathonKeyboard.UI 1.0
import MarathonKeyboard.Layouts 1.0

Rectangle {
    id: keyboard

    property real scaleFactor: 1.0

    property color backgroundColor: "#1E1E1E"
    property color keyBackgroundColor: "#2D2D30"
    property color keyPressedColor: "#007ACC"
    property color textColor: "#FFFFFF"
    property color textSecondaryColor: "#A0A0A0"
    property color borderColor: "#3E3E42"
    property real borderRadius: 4
    property real keySpacing: 4

    signal logMessage(string category, string message)
    signal hapticRequested(string intensity)

    property bool active: false
    property string currentLayout: "qwerty"
    property bool shifted: false
    property bool capsLock: false
    property bool predictionEnabled: true
}
