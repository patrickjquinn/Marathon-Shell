// Marathon Virtual Keyboard - Input Context
// Manages input field focus and provides proper key event handling
// OPTIMIZED for low-latency text input
import QtQuick
import MarathonOS.Shell

Item {
    id: inputContext

    // PERFORMANCE: visible false reduces overhead when not managing focus
    visible: false
    width: 0
    height: 0

    // Track if we're in an input field using Qt.inputMethod
    readonly property bool hasActiveFocus: Qt.inputMethod && Qt.inputMethod.visible

    // Input mode (for context-aware predictions and layout switching)
    property string inputMode: "text" // text, email, url, number, phone

    // Recommended keyboard layout based on input type
    readonly property string recommendedLayout: {
        switch (inputMode) {
        case "email":
            return "email";
        case "url":
            return "url";
        case "number":
            return "number";
        case "phone":
            return "phone";
        default:
            return "qwerty";
        }
    }

    // Context-aware keyboard behavior flags (based on input type)
    readonly property bool shouldAutoCapitalize: {
        switch (inputMode) {
        case "email":
            return false;
        case "url":
            return false;
        case "number":
            return false;
        case "phone":
            return false;
        default:
            return true;  // text, search
        }
    }

    readonly property bool shouldAutoCorrect: {
        switch (inputMode) {
        case "email":
            return false;  // Don't correct email addresses
        case "url":
            return false;    // Don't correct URLs
        case "number":
            return false;
        case "phone":
            return false;
        default:
            return true;
        }
    }

    readonly property bool shouldShowPredictions: {
        switch (inputMode) {
        case "url":
            return true;     // ISSUE D FIX: Show domain suggestions in URL mode
        case "email":
            return true;   // Show email domain suggestions
        case "number":
            return false;
        case "phone":
            return false;
        default:
            return true;  // Show for text, search
        }
    }

    signal textInserted(string text)
    signal backspacePressed
    signal enterPressed

    // Monitor Qt.inputMethod visible state
    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() {
            if (Qt.inputMethod.visible) {
                Logger.info("InputContext", "Input field focused");
                detectInputMode();
            } else {
                Logger.info("InputContext", "Input field unfocused");
            }
        }
    }

    // Insert text at cursor position
    function insertText(text) {
        // Qt.inputMethod.commit() in Qt6 doesn't take arguments
        // Text input is handled by C++ IME backend (InputMethodEngine)
        // This function is kept for API compatibility
        textInserted(text);
        Logger.info("InputContext", "Text input signaled: " + text);
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

        Logger.info("InputContext", "Replaced '" + currentWord + "' with: " + newWord);
    }

    // Get current word being typed
    function getCurrentWord() {
        // NOTE: This is a simplified version - in reality we'd need to query
        // the actual input field's text. For now, we track it in MarathonKeyboard.
        // This function is kept for API compatibility but may return empty string.

        Logger.warn("InputContext", "getCurrentWord() called - should use keyboard.currentWord instead");
        return "";
    }

    // Detect input mode from focused input
    function detectInputMode() {
        if (!Qt.inputMethod) {
            inputMode = "text";
            Logger.warn("InputContext", "Qt.inputMethod not available, defaulting to text mode");
            return;
        }

        // Read Qt.inputMethod hints
        var hints = Qt.inputMethod.inputItemHints;

        // Handle undefined hints (happens when keyboard is manually invoked without input focus)
        if (typeof hints === 'undefined' || hints === null) {
            inputMode = "text";
            Logger.warn("InputContext", "Input hints undefined (no focused input field), defaulting to text mode");
            return;
        }

        // ISSUE C FIX: More robust hint detection
        // Check for email
        if (hints & Qt.ImhEmailCharactersOnly) {
            inputMode = "email";
        } else
        // Check for URL - also detect if NoAutoUppercase is set with UrlCharactersOnly
        if (hints & Qt.ImhUrlCharactersOnly || ((hints & Qt.ImhNoAutoUppercase) && (hints & Qt.ImhNoPredictiveText))) {
            inputMode = "url";
        } else
        // Check for numbers only
        if (hints & Qt.ImhDigitsOnly) {
            inputMode = "number";
        } else
        // Check for phone number
        if (hints & Qt.ImhDialableCharactersOnly) {
            inputMode = "phone";
        } else
        // Default to text
        {
            inputMode = "text";
        }

        Logger.info("InputContext", "Detected input mode: " + inputMode + " (hints: " + hints + ", recommended layout: " + recommendedLayout + ")");
    }
}
