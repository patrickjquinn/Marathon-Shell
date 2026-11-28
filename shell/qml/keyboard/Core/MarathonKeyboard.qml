pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick

Rectangle {
    id: keyboard

    property bool active: false
    property string currentLayout: "dynamic"
    property bool shifted: false
    property bool capsLock: false
    property string currentWord: ""
    // Hints of the field being typed into; search, password, URL and number fields opt out of composing.
    property int fieldHints: 0
    readonly property bool fieldWantsPlainInput: (fieldHints & (Qt.ImhNoPredictiveText | Qt.ImhSensitiveData | Qt.ImhHiddenText | Qt.ImhUrlCharactersOnly | Qt.ImhEmailCharactersOnly | Qt.ImhDigitsOnly | Qt.ImhFormattedNumbersOnly | Qt.ImhDialableCharactersOnly)) !== 0
    property var currentPredictions: []
    property real lastSpaceTime: 0
    property real lastShiftTime: 0
    readonly property string sentenceEndingPunctuation: "!.?"
    property InputContext inputContext
    property bool showLanguageSelector: false
    property string lastCorrectedWord: ""
    property string lastOriginalWord: ""
    property bool canUndoAutoCorrect: false
    property string recentContext: ""
    // The space after an accepted prediction, which punctuation moves past.
    property bool autoSpaced: false
    readonly property string weakSpacePunctuation: ".,!?;:"
    // The last character the keyboard typed, or "" when it does not know what the cursor follows.
    // It decides capitals over the field's report, which can lag behind fast typing.
    property string lastTyped: ""
    // Where each letter of currentWord was tapped, "x,y", for the corrections.
    property var currentTaps: []
    // Where the key now typing went down, until handleKeyPress takes it.
    property string pendingTap: ""
    // The word a swipe just typed, with its space: backspace takes it whole,
    // and a suggestion replaces it.
    property string swipedWord: ""
    // What a slide off backspace would delete.
    property string pendingDelete: ""

    signal layoutChanged(string layout)
    signal dismissRequested

    function lastWord() {
        var words = keyboard.recentContext.trim().split(" ");
        return words[words.length - 1] || "";
    }

    function isLetter(text) {
        return text.length === 1 && text.toLowerCase() !== text.toUpperCase();
    }

    function tapsText() {
        return keyboard.currentTaps.join(";");
    }

    function remember(word) {
        if (keyboard.fieldWantsPlainInput || word.length === 0)
            return;
        Dictionary.learn(keyboard.lastWord(), word);
        var words = keyboard.recentContext.trim().split(" ").filter(w => w.length > 0);
        words.push(word);
        keyboard.recentContext = words.slice(-2).join(" ");
    }

    function handleKeyPress(text) {
        var tap = keyboard.pendingTap;
        keyboard.pendingTap = "";
        keyboard.swipedWord = "";
        var movedSpace = keyboard.autoSpaced && keyboard.weakSpacePunctuation.indexOf(text) !== -1 && inputContextInstance.replaceTextBeforeCursor(" ", text + " ");
        keyboard.autoSpaced = false;
        keyboard.canUndoAutoCorrect = false;
        if (!movedSpace) {
            keyboard.currentWord += text;
            if (keyboard.isLetter(text))
                keyboard.currentTaps = keyboard.currentTaps.concat([tap]);
            inputContextInstance.insertText(text);
        }
        keyboard.lastTyped = text.slice(-1);
        if (keyboard.sentenceEndingPunctuation.indexOf(text) !== -1) {
            keyboard.recentContext = "";
            if (inputContextInstance.shouldAutoCapitalize && !keyboard.capsLock) {
                keyboard.shifted = true;
                keyboard.currentWord = "";
                keyboard.currentPredictions = [];
                return;
            }
        }
        if (text === "," || (inputContextInstance.inputMode === "text" && !inputContextInstance.isWordText(text)))
            keyboard.currentWord = "";

        if (keyboard.shifted && !keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = false;
        updatePredictions();
    }

    function handleBackspace() {
        keyboard.autoSpaced = false;
        keyboard.lastTyped = "";
        if (keyboard.swipedWord !== "") {
            var swiped = keyboard.swipedWord;
            keyboard.swipedWord = "";
            if (inputContextInstance.deleteBeforeCursor(swiped)) {
                keyboard.currentPredictions = [];
                return;
            }
        }
        if (keyboard.canUndoAutoCorrect && keyboard.currentWord.length === 0) {
            keyboard.canUndoAutoCorrect = false;
            var undone = inputContextInstance.replaceTextBeforeCursor(keyboard.lastCorrectedWord + " ", keyboard.lastOriginalWord + " ");
            if (undone) {
                // Typed again as it was: the word is theirs.
                Dictionary.learn("", keyboard.lastOriginalWord);
                keyboard.lastOriginalWord = "";
                keyboard.lastCorrectedWord = "";
                return;
            }
            keyboard.lastOriginalWord = "";
            keyboard.lastCorrectedWord = "";
        }
        keyboard.canUndoAutoCorrect = false;
        inputContextInstance.handleBackspace();
        if (keyboard.currentWord.length > 0) {
            if (keyboard.isLetter(keyboard.currentWord.slice(-1)))
                keyboard.currentTaps = keyboard.currentTaps.slice(0, -1);
            keyboard.currentWord = keyboard.currentWord.slice(0, -1);
            updatePredictions();
        }
        if (keyboard.currentWord === "")
            autoShiftTimer.restart();
    }

    function handleSpace() {
        var now = Date.now();
        var isDoubleTap = (now - keyboard.lastSpaceTime < 300) && keyboard.currentWord.length === 0;
        keyboard.autoSpaced = false;
        keyboard.swipedWord = "";
        if (isDoubleTap && inputContextInstance.shouldAutoCapitalize && inputContextInstance.insertDoubleSpacePeriod()) {
            keyboard.canUndoAutoCorrect = false;
            keyboard.shifted = true;
            keyboard.lastSpaceTime = 0;
            keyboard.recentContext = "";
            keyboard.lastTyped = ".";
            keyboard.currentPredictions = [];
            return;
        }
        var word = keyboard.currentWord;
        keyboard.canUndoAutoCorrect = false;
        if (word.length > 0) {
            // A word stays a typo when its correction can't go in: not learnt.
            var settled = true;
            // Only a word of letters is a typo: "2q" or "v1.2" is meant.
            if (inputContextInstance.shouldAutoCorrect && keyboard.currentTaps.length === word.replace(/'/g, "").length) {
                var corrected = Dictionary.correctionFor(word, keyboard.tapsText(), keyboard.lastWord());
                if (corrected !== word) {
                    settled = inputContextInstance.replaceCurrentWord(corrected);
                    if (settled) {
                        keyboard.lastOriginalWord = word;
                        keyboard.lastCorrectedWord = corrected;
                        keyboard.canUndoAutoCorrect = true;
                        word = corrected;
                    }
                }
            }
            keyboard.currentWord = "";
            if (settled)
                keyboard.remember(word);
        }
        inputContextInstance.insertText(" ");
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize && atSentenceStart())
            keyboard.shifted = true;
        keyboard.lastSpaceTime = now;
        updatePredictions();
    }

    function handleEnter() {
        if (keyboard.currentWord.length > 0) {
            keyboard.remember(keyboard.currentWord);
            keyboard.currentWord = "";
        }
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = true;

        keyboard.canUndoAutoCorrect = false;
        keyboard.autoSpaced = false;
        keyboard.swipedWord = "";
        keyboard.lastTyped = "";
        keyboard.recentContext = "";
        keyboard.currentPredictions = [];
        inputContextInstance.handleEnter();
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

    // A word in the case shift asks for.
    function shiftedWord(word) {
        if (keyboard.capsLock)
            return word.toUpperCase();
        if (keyboard.shifted)
            return word.charAt(0).toUpperCase() + word.slice(1);
        return word;
    }

    function handleSwipe(points) {
        var words = Dictionary.swipe(points, keyboard.lastWord());
        if (words.length === 0)
            return;
        if (keyboard.currentWord.length > 0)
            keyboard.handleSpace();
        var word = keyboard.shiftedWord(words[0]);
        // A swiped word after a word or punctuation gets its space first.
        var before = inputContextInstance.wordsBeforeCursor(1);
        var spaced = before !== "" && !/\s$/.test(before);
        inputContextInstance.insertText((spaced ? " " : "") + word + " ");
        keyboard.swipedWord = word + " ";
        keyboard.autoSpaced = true;
        keyboard.canUndoAutoCorrect = false;
        keyboard.lastTyped = word.slice(-1);
        keyboard.remember(words[0]);
        if (keyboard.shifted && !keyboard.capsLock)
            keyboard.shifted = false;
        keyboard.currentPredictions = words.slice(1, 4).map(w => keyboard.shiftedWord(w));
    }

    function acceptPrediction(word) {
        if (keyboard.swipedWord !== "") {
            if (inputContextInstance.replaceTextBeforeCursor(keyboard.swipedWord, word + " ")) {
                keyboard.swipedWord = word + " ";
                keyboard.remember(word);
                keyboard.currentPredictions = [];
            }
            return;
        }
        var typed = keyboard.currentWord;
        if (typed.length === 0) {
            inputContextInstance.insertText(word + " ");
        } else if (!inputContextInstance.replaceCurrentWord(word + " ")) {
            // A field that reports no surrounding text can only be completed.
            if (!word.startsWith(typed))
                return;
            inputContextInstance.insertText(word.slice(typed.length) + " ");
        }
        keyboard.canUndoAutoCorrect = false;
        keyboard.autoSpaced = true;
        keyboard.lastTyped = word.slice(-1);
        keyboard.currentWord = "";
        keyboard.remember(word);
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize && atSentenceStart())
            keyboard.shifted = true;
        updatePredictions();
    }

    function paste(text) {
        inputContextInstance.insertText(text);
        keyboard.forgetWord();
        keyboard.lastTyped = text.slice(-1);
    }

    // The cursor moved or text went without the keyboard knowing the word.
    function forgetWord() {
        keyboard.currentWord = "";
        keyboard.currentPredictions = [];
        keyboard.autoSpaced = false;
        keyboard.canUndoAutoCorrect = false;
        keyboard.swipedWord = "";
        keyboard.lastTyped = "";
        keyboard.recentContext = "";
    }

    function moveCursor(direction) {
        inputContextInstance.sendCursorKey(direction < 0 ? Qt.Key_Left : Qt.Key_Right);
        keyboard.forgetWord();
        autoShiftTimer.restart();
        if (SettingsManagerCpp.keyboardHapticStrength !== "off")
            HapticManager.light();
    }

    function deleteWords(count) {
        var text = inputContextInstance.wordsBeforeCursor(count);
        keyboard.pendingDelete = "";
        if (text === "" || !inputContextInstance.deleteBeforeCursor(text))
            return;
        keyboard.forgetWord();
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize)
            keyboard.shifted = inputContextInstance.atSentenceStart();
    }

    function atSentenceStart() {
        if (keyboard.lastTyped !== "")
            return keyboard.sentenceEndingPunctuation.indexOf(keyboard.lastTyped) !== -1;
        return inputContextInstance.atSentenceStart();
    }

    function updatePredictions() {
        if (!inputContextInstance.shouldShowPredictions) {
            keyboard.currentPredictions = [];
            return;
        }
        if (keyboard.currentWord.length === 0) {
            var before = keyboard.lastWord();
            keyboard.currentPredictions = before ? Dictionary.nextWords(before).map(w => keyboard.shiftedWord(w)) : [];
            return;
        }
        var isEmail = inputContextInstance.inputMode === "email";
        var isUrl = inputContextInstance.inputMode === "url";
        if (isEmail || isUrl) {
            if (DomainSuggestions.shouldShowDomainSuggestions(keyboard.currentWord, isEmail, isUrl)) {
                var domainSugs = DomainSuggestions.getSuggestions(keyboard.currentWord, isEmail);
                if (domainSugs.length > 0) {
                    keyboard.currentPredictions = domainSugs;
                    return;
                }
            }
        }
        Dictionary.suggest(keyboard.currentWord, keyboard.tapsText(), keyboard.lastWord());
        keyboard.currentPredictions = Dictionary.suggestedFor === keyboard.currentWord ? Dictionary.suggestions : [];
    }

    function updateCurrentWord() {
        updatePredictions();
    }

    function show() {
        keyboard.active = true;
        inputContextInstance.detectInputMode();
        keyboard.lastTyped = "";
        updateAutoShift();
    }

    // Shift follows the text before the cursor: on at a sentence's start.
    // Checked again once an app's field has sent its text over.
    function updateAutoShift() {
        autoShiftTimer.restart();
        if (keyboard.capsLock || keyboard.currentWord !== "")
            return;
        keyboard.shifted = inputContextInstance.shouldAutoCapitalize && inputContextInstance.atSentenceStart();
    }

    // App fields commit their hints after the keyboard opens, and switching fields keeps it open.
    // Qt's text-input v2 reports the hints as changed on every commit, so only a real change counts.
    function refreshFieldHints() {
        var hints = typeof InputMethodEngine !== "undefined" ? InputMethodEngine.focusHints() : 0;
        if (hints === keyboard.fieldHints)
            return;
        keyboard.fieldHints = hints;
        keyboard.lastTyped = "";
        inputContextInstance.detectInputMode();
        updateAutoShift();
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
        keyboard.autoSpaced = false;
        keyboard.lastTyped = "";
    }

    function clear() {
        keyboard.currentWord = "";
        keyboard.currentPredictions = [];
        keyboard.swipedWord = "";
    }

    width: parent ? parent.width : 0
    implicitHeight: mainColumn.implicitHeight
    height: active ? implicitHeight : 0
    color: MColors.eink ? MColors.background : Qt.rgba(0.04, 0.04, 0.05, 1)
    onActiveChanged: {
        if (active) {
            keyboard.fieldHints = typeof InputMethodEngine !== "undefined" ? InputMethodEngine.focusHints() : 0;
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
            keyboard.autoSpaced = false;
            keyboard.lastTyped = "";
        }
    }
    onCurrentLayoutChanged: {
        if (!capsLock)
            shifted = false;
    }
    onCurrentWordChanged: {
        if (currentWord.length === 0)
            currentTaps = [];
    }

    Timer {
        id: autoShiftTimer

        interval: 80
        onTriggered: {
            if (!keyboard.capsLock && keyboard.currentWord === "" && keyboard.lastTyped === "")
                keyboard.shifted = inputContextInstance.shouldAutoCapitalize && inputContextInstance.atSentenceStart();
        }
    }

    Connections {
        function onSuggestionsChanged() {
            if (inputContextInstance.shouldShowPredictions && keyboard.currentWord !== "" && keyboard.currentWord === Dictionary.suggestedFor)
                keyboard.currentPredictions = Dictionary.suggestions;
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
                pendingDelete: keyboard.pendingDelete
                // The first word is what a space will leave: lit while it corrects.
                correcting: keyboard.currentWord !== "" && Dictionary.suggestedFor === keyboard.currentWord && Dictionary.correction !== keyboard.currentWord
                predictions: keyboard.currentPredictions
                onPredictionSelected: function (word) {
                    keyboard.acceptPrediction(word);
                }
                onPasteRequested: function (text) {
                    keyboard.paste(text);
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
            KeyboardTouch {
                id: keyboardTouch

                anchors.fill: parent
                z: 100
                enabled: keyboard.active && keyboard.currentLayout !== "emoji"
                layout: keyboardLayoutContainer.layoutMap[keyboard.currentLayout]
                swipeEnabled: SettingsManagerCpp.keyboardSwipeTyping && !keyboard.fieldWantsPlainInput && (keyboard.currentLayout === "dynamic" || keyboard.currentLayout === "qwerty")
                trailColor: MColors.accent
                onLetterTapped: function (x, y) {
                    keyboard.pendingTap = x.toFixed(1) + "," + y.toFixed(1);
                }
                onSwiped: function (points) {
                    keyboard.handleSwipe(points);
                }
                onCursorStep: function (direction) {
                    keyboard.moveCursor(direction);
                }
                onDeletePreview: function (words) {
                    keyboard.pendingDelete = words > 0 ? inputContextInstance.wordsBeforeCursor(words) : "";
                }
                onDeleteWords: function (words) {
                    keyboard.deleteWords(words);
                }
                onLettersMoved: function (keys, pitch) {
                    Dictionary.setKeys(keys, pitch);
                }
            }
        }

        LanguageSelector {
            id: languageSelector

            width: parent.width
            visible: keyboard.showLanguageSelector
            onDismissed: {
                keyboard.showLanguageSelector = false;
            }
        }
    }

    inputContext: InputContext {
        id: inputContextInstance
        keyboard: keyboard
        autoCapitalizeEnabled: SettingsManagerCpp.keyboardAutoCapitalize && !(keyboard.fieldHints & Qt.ImhNoAutoUppercase) && !keyboard.fieldWantsPlainInput
        autoCorrectEnabled: SettingsManagerCpp.keyboardAutoCorrection && !keyboard.fieldWantsPlainInput
        predictionsEnabled: SettingsManagerCpp.keyboardPredictiveText && !keyboard.fieldWantsPlainInput

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
            duration: MMotion.ms(100)
            easing.type: Easing.OutCubic
        }
    }
}
