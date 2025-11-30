// Marathon Virtual Keyboard - Input Context
// Manages input field focus and provides proper key event handling
// OPTIMIZED for low-latency text input
import QtQuick

Item {
    id: inputContext

    // PERFORMANCE: visible false reduces overhead when not managing focus
    visible: false
    width: 0
    height: 0

    // Track if we're in an input field using Qt.inputMethod
    readonly property bool hasActiveFocus: Qt.inputMethod && Qt.inputMethod.visible

    // Input mode (for context-aware predictions)
    property string inputMode: "text" // text, email, url, number

    signal textInserted(string text)
    signal backspacePressed
    signal enterPressed

    // Monitor Qt.inputMethod visible state
    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() {
            if (Qt.inputMethod.visible) {
                keyboard.logMessage("InputContext", "Input field focused");
                detectInputMode();
            } else {
                keyboard.logMessage("InputContext", "Input field unfocused");
            }
        }
    }

    // Insert text at cursor position
    function insertText(text) {
        // Qt.inputMethod.commit() in Qt6 doesn't take arguments
        // Text input is handled by C++ IME backend (InputMethodEngine)
        // This function is kept for API compatibility
        textInserted(text);
        keyboard.logMessage("InputContext", "Text input signaled: " + text);
    }

    // Handle backspace
    function handleBackspace() {
        // Send backspace through the C++ IME backend (already wired in VirtualKeyboard.qml)
        backspacePressed();
    }

    // Handle enter/return
    function handleEnter() {
        // Send enter through the C++ IME backend
        enterPressed();
    }

    // Replace current word with suggestion
    function replaceCurrentWord(newWord) {
        var currentWord = getCurrentWord();
        if (currentWord.length === 0) {
            // No current word, just insert the new word
            insertText(newWord);
            return;
        }

        // Delete the current word (send backspace for each character)
        for (var i = 0; i < currentWord.length; i++) {
            handleBackspace();
        }

        // Insert the new word
        insertText(newWord);

        keyboard.logMessage("InputContext", "Replaced '" + currentWord + "' with: " + newWord);
    }

    // Get current word being typed
    function getCurrentWord() {
        // NOTE: This is a simplified version - in reality we'd need to query
        // the actual input field's text. For now, we track it in MarathonKeyboard.
        // This function is kept for API compatibility but may return empty string.

        keyboard.logMessage("InputContext", "getCurrentWord() called - should use keyboard.currentWord instead");
        return "";
    }

    // Detect input mode from focused input
    function detectInputMode() {
        // For now, default to "text" - could be enhanced to detect from Qt.inputMethod hints
        inputMode = "text";
        keyboard.logMessage("InputContext", "Input mode: " + inputMode);
    }
}
