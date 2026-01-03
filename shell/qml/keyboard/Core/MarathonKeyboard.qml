import MarathonOS.Shell
import QtQuick

Rectangle {
    id: keyboard

    property bool active: false
    property string currentLayout: "dynamic"
    property bool shifted: false
    property bool capsLock: false
    property string currentWord: ""
    property var currentPredictions: []
    property real lastSpaceTime: 0
    property real lastShiftTime: 0
    readonly property string sentenceEndingPunctuation: "!.?"
    readonly property string wordSeparators: ",.!?:;"
    property InputContext inputContext
    property bool showLanguageSelector: false
    property string lastCorrectedWord: ""
    property string lastOriginalWord: ""
    property bool canUndoAutoCorrect: false
    property string recentContext: ""

    signal keyPressed(string text)
    signal backspace
    signal enter
    signal layoutChanged(string layout)
    signal dismissRequested

    function handleKeyPress(text) {
        keyboard.currentWord += text;
        inputContextInstance.insertText(text);
        keyboard.keyPressed(text);
        if (inputContextInstance.shouldShowPredictions)
            updatePredictions();
        else
            keyboard.currentPredictions = [];
        if (keyboard.sentenceEndingPunctuation.indexOf(text) !== -1 && inputContextInstance.shouldAutoCapitalize) {
            if (!keyboard.capsLock) {
                keyboard.shifted = true;
                keyboard.currentWord = "";
            }
            return;
        }
        if (text === ",")
            keyboard.currentWord = "";

        if (keyboard.shifted && !keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = false;
    }

    function handleBackspace() {
        if (keyboard.canUndoAutoCorrect && keyboard.currentWord.length === 0) {
            var correctedLen = keyboard.lastCorrectedWord.length + 1;
            for (var i = 0; i < correctedLen; i++) {
                inputContextInstance.handleBackspace();
                keyboard.backspace();
            }
            inputContextInstance.insertText(keyboard.lastOriginalWord + " ");
            keyboard.keyPressed(keyboard.lastOriginalWord + " ");
            keyboard.canUndoAutoCorrect = false;
            keyboard.lastOriginalWord = "";
            keyboard.lastCorrectedWord = "";
            return;
        }
        keyboard.canUndoAutoCorrect = false;
        inputContextInstance.handleBackspace();
        if (keyboard.currentWord.length > 0) {
            keyboard.currentWord = keyboard.currentWord.slice(0, -1);
            if (keyboard.currentWord.length === 0)
                keyboard.currentPredictions = [];
            else
                updatePredictions();
        }
        keyboard.backspace();
    }

    function handleSpace() {
        var now = Date.now();
        var isDoubleTap = (now - keyboard.lastSpaceTime < 300) && keyboard.currentWord.length === 0;
        if (isDoubleTap && inputContextInstance.shouldAutoCapitalize) {
            inputContextInstance.handleBackspace();
            inputContextInstance.insertText(". ");
            keyboard.keyPressed(". ");
            keyboard.shifted = true;
            keyboard.lastSpaceTime = 0;
            keyboard.recentContext = "";
            return;
        }
        var wordToAdd = "";
        if (keyboard.currentWord.length > 0) {
            var originalWord = keyboard.currentWord;
            if (inputContextInstance.shouldAutoCorrect) {
                var correctedWord = AutoCorrect.correct(originalWord);
                if (correctedWord !== originalWord) {
                    inputContextInstance.replaceCurrentWord(correctedWord);
                    Dictionary.learnWord(correctedWord);
                    keyboard.lastOriginalWord = originalWord;
                    keyboard.lastCorrectedWord = correctedWord;
                    keyboard.canUndoAutoCorrect = true;
                    wordToAdd = correctedWord;
                } else {
                    Dictionary.learnWord(originalWord);
                    keyboard.canUndoAutoCorrect = false;
                    wordToAdd = originalWord;
                }
            } else {
                keyboard.canUndoAutoCorrect = false;
                wordToAdd = originalWord;
            }
            keyboard.currentWord = "";
        }
        if (wordToAdd.length > 0) {
            var contextWords = keyboard.recentContext.trim().split(" ").filter(function (w) {
                return w.length > 0;
            });
            contextWords.push(wordToAdd.toLowerCase());
            if (contextWords.length > 2)
                contextWords = contextWords.slice(-2);

            keyboard.recentContext = contextWords.join(" ");
        }
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = true;

        inputContextInstance.insertText(" ");
        keyboard.keyPressed(" ");
        keyboard.lastSpaceTime = now;
        updatePredictions();
    }

    function handleEnter() {
        if (keyboard.currentWord.length > 0) {
            Dictionary.learnWord(keyboard.currentWord);
            keyboard.currentWord = "";
        }
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = true;

        inputContextInstance.handleEnter();
        keyboard.enter();
    }

    function handleShift() {
        var now = Date.now();
        var isDoubleTap = (now - keyboard.lastShiftTime < 300);
        if (keyboard.capsLock) {
            keyboard.capsLock = false;
            keyboard.shifted = false;
        } else if (isDoubleTap && keyboard.shifted) {
            keyboard.capsLock = true;
            keyboard.shifted = true;
        } else {
            keyboard.shifted = !keyboard.shifted;
        }
        keyboard.lastShiftTime = now;
    }

    function acceptPrediction(word) {
        var charsToDelete = keyboard.currentWord.length;
        for (var i = 0; i < charsToDelete; i++) {
            keyboard.backspace();
        }
        inputContextInstance.insertText(word + " ");
        keyboard.keyPressed(word + " ");
        Dictionary.learnWord(word);
        keyboard.currentWord = "";
        keyboard.currentPredictions = [];
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = true;
    }

    function updatePredictions() {
        if (keyboard.currentWord.length === 0) {
            var phrasePreds = Dictionary.getPhraseCompletions(keyboard.recentContext);
            if (phrasePreds.length > 0) {
                keyboard.currentPredictions = phrasePreds.slice(0, 5);
                return;
            }
            keyboard.currentPredictions = [];
            return;
        }
        var isEmail = inputContextInstance.inputMode === "email";
        var isUrl = inputContextInstance.inputMode === "url";
        if (isEmail || isUrl) {
            if (domainSuggestions.shouldShowDomainSuggestions(keyboard.currentWord, isEmail, isUrl)) {
                var domainSugs = domainSuggestions.getSuggestions(keyboard.currentWord, isEmail);
                if (domainSugs.length > 0) {
                    keyboard.currentPredictions = domainSugs;
                    return;
                }
            }
        }
        if (inputContextInstance.shouldShowPredictions) {
            Dictionary.predict(keyboard.currentWord);
            keyboard.currentPredictions = Dictionary.cachedPredictions;
        } else {
            keyboard.currentPredictions = [];
        }
    }

    function updateCurrentWord() {
        updatePredictions();
    }

    function show() {
        keyboard.active = true;
        inputContextInstance.detectInputMode();
        if (inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = true;
        else
            keyboard.shifted = false;
    }

    function hide() {
        keyboard.active = false;
        keyboard.currentWord = "";
        keyboard.currentPredictions = [];
        keyboard.recentContext = "";
        keyboard.shifted = false;
        keyboard.capsLock = false;
        keyboard.canUndoAutoCorrect = false;
        keyboard.lastOriginalWord = "";
        keyboard.lastCorrectedWord = "";
        keyboard.lastSpaceTime = 0;
    }

    function clear() {
        keyboard.currentWord = "";
        keyboard.currentPredictions = [];
    }

    width: parent ? parent.width : 0
    implicitHeight: mainColumn.implicitHeight
    height: active ? implicitHeight : 0
    color: "#1a1a1a"
    border.width: 0
    layer.enabled: true
    layer.smooth: true
    onActiveChanged: {
        if (active) {
            show();
        } else {
            keyboard.currentWord = "";
            keyboard.currentPredictions = [];
            keyboard.recentContext = "";
            keyboard.shifted = false;
            keyboard.capsLock = false;
            keyboard.canUndoAutoCorrect = false;
            keyboard.lastOriginalWord = "";
            keyboard.lastCorrectedWord = "";
            keyboard.lastSpaceTime = 0;
        }
    }
    onCurrentLayoutChanged: {
        if (!capsLock)
            shifted = false;
    }
    onCurrentWordChanged: {
        if (currentWord.length === 0)
            currentPredictions = [];
    }

    DomainSuggestions {
        id: domainSuggestions
    }

    Connections {
        function onCachedPredictionsChanged() {
            if (inputContextInstance.shouldShowPredictions && keyboard.currentWord === Dictionary.lastPredictionPrefix)
                keyboard.currentPredictions = Dictionary.cachedPredictions;
        }

        target: Dictionary
    }

    Column {
        id: mainColumn

        anchors.fill: parent
        spacing: 0

        Loader {
            id: predictionLoader

            width: parent.width
            height: Math.round(40 * Constants.scaleFactor)
            active: true
            visible: true
            asynchronous: false

            sourceComponent: PredictionBar {
                width: parent.width
                currentWord: keyboard.currentWord
                predictions: keyboard.currentPredictions
                onPredictionSelected: function (word) {
                    keyboard.acceptPrediction(word);
                }
            }
        }

        Item {
            id: keyboardLayoutContainer

            property var layoutMap: {
                "qwerty": qwertyLayout,
                "dynamic": dynamicLayout,
                "symbols": symbolLayout,
                "email": emailLayout,
                "url": urlLayout,
                "number": numberLayout,
                "phone": phoneLayout,
                "emoji": emojiLayout,
                "terminal": terminalLayout
            }

            width: parent.width
            height: implicitHeight
            implicitHeight: layoutMap[keyboard.currentLayout].implicitHeight
            visible: keyboard.active

            QwertyLayout {
                id: qwertyLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "qwerty"
                shifted: keyboard.shifted
                capsLock: keyboard.capsLock
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onShiftClicked: {
                    keyboard.handleShift();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
                onLanguageSwitchClicked: {
                    keyboard.showLanguageSelector = true;
                }
            }

            SymbolLayout {
                id: symbolLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "symbols"
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
            }

            EmailLayout {
                id: emailLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "email"
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
            }

            UrlLayout {
                id: urlLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "url"
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
            }

            NumberLayout {
                id: numberLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "number"
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
            }

            PhoneLayout {
                id: phoneLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "phone"
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
            }

            EmojiLayout {
                id: emojiLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "emoji"
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
            }

            TerminalLayout {
                id: terminalLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "terminal"
                shifted: keyboard.shifted
                capsLock: keyboard.capsLock
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onShiftClicked: {
                    keyboard.handleShift();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
                onCursorKeyClicked: function (key) {
                    inputContextInstance.sendCursorKey(key);
                }
            }

            DynamicLayout {
                id: dynamicLayout

                anchors.fill: parent
                anchors.margins: 0
                visible: keyboard.currentLayout === "dynamic"
                shifted: keyboard.shifted
                capsLock: keyboard.capsLock
                onKeyClicked: function (text) {
                    keyboard.handleKeyPress(text);
                }
                onBackspaceClicked: {
                    keyboard.handleBackspace();
                }
                onEnterClicked: {
                    keyboard.handleEnter();
                }
                onShiftClicked: {
                    keyboard.handleShift();
                }
                onSpaceClicked: {
                    keyboard.handleSpace();
                }
                onLayoutSwitchClicked: function (layout) {
                    keyboard.currentLayout = layout;
                }
                onDismissClicked: {
                    keyboard.dismissRequested();
                }
                onLanguageSwitchClicked: {
                    keyboard.showLanguageSelector = !keyboard.showLanguageSelector;
                }
            }
        }

        LanguageSelector {
            id: languageSelector

            width: parent.width
            visible: keyboard.showLanguageSelector
            onLanguageSelected: function (languageId) {
                if (typeof WordEngine !== 'undefined' && WordEngine !== null)
                    WordEngine.setLanguage(LanguageManager.currentLayout.dictionary);
            }
            onDismissed: {
                keyboard.showLanguageSelector = false;
            }
        }
    }

    inputContext: InputContext {
        id: inputContextInstance

        onTextInserted: function (text) {
            if (text === " " || text === "\n")
                keyboard.currentWord = "";
        }
        onBackspacePressed: {
            keyboard.updateCurrentWord();
        }
        onRecommendedLayoutChanged: {
            if (keyboard.active && recommendedLayout !== keyboard.currentLayout)
                keyboard.currentLayout = recommendedLayout;
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }
}
