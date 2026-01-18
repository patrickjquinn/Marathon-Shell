import QtQuick

Item {
    id: inputContext

    visible: false
    width: 0
    height: 0

    readonly property bool hasActiveFocus: Qt.inputMethod && Qt.inputMethod.visible

    property string inputMode: "text"

    signal textInserted(string text)
    signal backspacePressed
    signal enterPressed

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

    function insertText(text) {
        textInserted(text);
        keyboard.logMessage("InputContext", "Text input signaled: " + text);
    }

    function handleBackspace() {
        backspacePressed();
    }

    function handleEnter() {
        enterPressed();
    }

    function replaceCurrentWord(newWord) {
        var currentWord = getCurrentWord();
        if (currentWord.length === 0) {
            insertText(newWord);
            return;
        }

        for (var i = 0; i < currentWord.length; i++) {
            handleBackspace();
        }

        insertText(newWord);

        keyboard.logMessage("InputContext", "Replaced '" + currentWord + "' with: " + newWord);
    }

    function getCurrentWord() {
        keyboard.logMessage("InputContext", "getCurrentWord() called - should use keyboard.currentWord instead");
        return "";
    }

    function detectInputMode() {
        inputMode = "text";
        keyboard.logMessage("InputContext", "Input mode: " + inputMode);
    }
}
