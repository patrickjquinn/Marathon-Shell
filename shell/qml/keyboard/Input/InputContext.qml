import QtQuick

Item {
    id: inputContext

    readonly property bool hasActiveFocus: Qt.inputMethod && Qt.inputMethod.visible
    property string inputMode: "text"
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
        case "terminal":
            return "terminal";
        default:
            return "dynamic";
        }
    }
    readonly property bool shouldAutoCapitalize: {
        switch (inputMode) {
        case "email":
        case "url":
        case "number":
        case "phone":
        case "terminal":
            return false;
        default:
            return true;
        }
    }
    readonly property bool shouldAutoCorrect: {
        switch (inputMode) {
        case "email":
        case "url":
        case "number":
        case "phone":
        case "terminal":
            return false;
        default:
            return true;
        }
    }
    readonly property bool shouldShowPredictions: {
        switch (inputMode) {
        case "url":
        case "email":
            return true;
        case "number":
        case "phone":
        case "terminal":
            return false;
        default:
            return true;
        }
    }

    signal textInserted(string text)
    signal backspacePressed
    signal enterPressed
    signal cursorKeyPressed(int key)

    function insertText(text) {
        textInserted(text);
    }

    function handleBackspace() {
        backspacePressed();
    }

    function handleEnter() {
        enterPressed();
    }

    function sendCursorKey(key) {
        cursorKeyPressed(key);
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
    }

    function getCurrentWord() {
        if (parent && parent.keyboard && parent.keyboard.currentWord)
            return parent.keyboard.currentWord;

        return "";
    }

    function detectInputMode() {
        if (!Qt.inputMethod) {
            inputMode = "text";
            return;
        }
        var hints = Qt.inputMethod.inputItemHints;
        if (typeof hints === 'undefined' || hints === null) {
            inputMode = "text";
            return;
        }
        if (hints & Qt.ImhEmailCharactersOnly)
            inputMode = "email";
        else if (hints & Qt.ImhUrlCharactersOnly || ((hints & Qt.ImhNoAutoUppercase) && (hints & Qt.ImhNoPredictiveText)))
            inputMode = "url";
        else if (hints & Qt.ImhDigitsOnly)
            inputMode = "number";
        else if (hints & Qt.ImhDialableCharactersOnly)
            inputMode = "phone";
        else
            inputMode = "text";
    }

    visible: false
    width: 0
    height: 0

    Connections {
        function onVisibleChanged() {
            if (Qt.inputMethod.visible)
                detectInputMode();
        }

        target: Qt.inputMethod
    }
}
