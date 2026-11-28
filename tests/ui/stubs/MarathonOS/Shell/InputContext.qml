import QtQuick

// The on-screen keyboard's text sink; records what it was sent.
QtObject {
    property var keyboard: null
    property string inputMode: "text"
    property string recommendedLayout: "dynamic"
    property bool autoCapitalizeEnabled: false
    property bool autoCorrectEnabled: false
    property bool predictionsEnabled: false
    property bool shouldAutoCapitalize: false
    property bool shouldAutoCorrect: false
    property bool shouldShowPredictions: false
    property bool hasActiveFocus: true
    property string text: ""

    signal textInserted(string text)
    signal backspacePressed
    signal enterPressed
    signal cursorKeyPressed(int key)

    function insertText(t) {
        text += t;
        textInserted(t);
    }
    function handleBackspace() {
        text = text.slice(0, -1);
        backspacePressed();
    }
    function handleEnter() {
        enterPressed();
    }
    function sendCursorKey(key) {
        cursorKeyPressed(key);
    }
    function replaceTextBeforeCursor(before, t) {
        return false;
    }
    function replaceCurrentWord(word) {
        return false;
    }
    function insertDoubleSpacePeriod() {
        return false;
    }
    function atSentenceStart() {
        return text.length === 0;
    }
    function isWordText(t) {
        return /\w/.test(t);
    }
    function getCurrentWord() {
        return "";
    }
    function wordsBeforeCursor(count) {
        return "";
    }
    function deleteBeforeCursor(t) {
        return false;
    }
    function detectInputMode() {
    }
}
