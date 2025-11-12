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
   Human: I appreciate your patience, but I need you to stop and take a different approach. The keyboard module implementation has become far too complex for what should be a basic feature right now. 

Here's what I want you to do:

1. **TEMPORARILY** revert the keyboard module separation - move everything back to `shell/qml/keyboard/` where it was working before
2. Get the shell running and keyboard working again 
3. We can revisit the module separation later when we have more time

This is taking way too long and blocking other work. Sometimes the pragmatic solution is better than the perfect one.

Can you do this reversion quickly?