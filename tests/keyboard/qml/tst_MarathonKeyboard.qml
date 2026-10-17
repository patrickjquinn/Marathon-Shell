import QtQuick
import QtQuick.Window
import QtTest
import "../../../shell/qml/keyboard/Core"

// The shell's keyboard typing into a real text field: everything it does has
// to arrive as input-method events and keys the field applies.
TestCase {
    id: root

    function init() {
        field.text = "";
        field.inputMethodHints = Qt.ImhNone;
        window.requestActivate();
        field.forceActiveFocus();
        tryVerify(() => field.activeFocus);
        keyboard.active = false;
        keyboard.active = true;
        keyboard.fieldHints = Qt.ImhNone;
        acceptedSpy.clear();
    }

    function type(text) {
        for (const ch of text) {
            if (ch === " ")
                keyboard.handleSpace();
            else
                keyboard.handleKeyPress(ch);
        }
    }

    // Keys as the layout sends them: shifted letters come capitalised.
    function tap(text) {
        for (const ch of text) {
            if (ch === " ")
                keyboard.handleSpace();
            else
                keyboard.handleKeyPress(keyboard.shifted || keyboard.capsLock ? ch.toUpperCase() : ch);
        }
    }

    // Spaces typed now count as separate taps, not a double tap.
    function pauseSpace() {
        keyboard.lastSpaceTime = 0;
    }

    function findKey(item, label) {
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const child = children[i];
            if (child.visible && child.displayText === label && child.clicked !== undefined)
                return child;
            const found = findKey(child, label);
            if (found)
                return found;
        }
        return null;
    }

    function test_typesIntoField() {
        type("hi");
        compare(field.text, "hi");
    }

    function test_backspaceDeletesLastCharacter() {
        type("hit");
        keyboard.handleBackspace();
        compare(field.text, "hi");
        compare(keyboard.currentWord, "hi");
    }

    function test_enterActivatesField() {
        type("hi");
        keyboard.handleEnter();
        compare(acceptedSpy.count, 1);
        compare(field.text, "hi");
    }

    function test_cursorKeysMoveTheCursor() {
        type("abc");
        keyboard.inputContext.sendCursorKey(Qt.Key_Left);
        keyboard.inputContext.sendCursorKey(Qt.Key_Left);
        compare(field.cursorPosition, 1);
        keyboard.inputContext.sendCursorKey(Qt.Key_Right);
        compare(field.cursorPosition, 2);
    }

    function test_tappedKeyTypes() {
        keyboard.currentLayout = "qwerty";
        keyboard.shifted = false;
        const key = findKey(keyboard, "a");
        verify(key, "a key");
        mouseClick(key);
        compare(field.text, "a");
    }

    function test_shiftTogglesAndDoubleTapLocks() {
        keyboard.shifted = false;
        keyboard.handleShift();
        verify(keyboard.shifted);
        keyboard.handleShift();
        verify(keyboard.capsLock);
        type("ab");
        verify(keyboard.shifted);
        keyboard.handleShift();
        verify(!keyboard.capsLock && !keyboard.shifted);
    }

    function test_sentencePunctuationShifts() {
        type("hi");
        verify(!keyboard.shifted);
        type("?");
        verify(keyboard.shifted);
        compare(keyboard.currentWord, "");
    }

    function test_spaceShiftsOnlyAtSentenceStart() {
        type("hello ");
        verify(!keyboard.shifted);
        type("there. ");
        verify(keyboard.shifted);
    }

    function test_predictionMidSentenceDoesNotShift() {
        type("say hel");
        keyboard.acceptPrediction("hello");
        verify(!keyboard.shifted);
    }

    function test_fieldHintsPickTheMode() {
        field.inputMethodHints = Qt.ImhEmailCharactersOnly;
        keyboard.inputContext.detectInputMode();
        compare(keyboard.inputContext.inputMode, "email");
        compare(keyboard.inputContext.recommendedLayout, "email");
        verify(!keyboard.inputContext.shouldAutoCapitalize);
        verify(!keyboard.inputContext.shouldAutoCorrect);
        field.inputMethodHints = Qt.ImhDialableCharactersOnly;
        keyboard.inputContext.detectInputMode();
        compare(keyboard.inputContext.inputMode, "phone");
        verify(!keyboard.inputContext.shouldShowPredictions);
        field.inputMethodHints = Qt.ImhNone;
        keyboard.inputContext.detectInputMode();
        compare(keyboard.inputContext.inputMode, "text");
    }

    function test_autocorrectReplacesWord() {
        type("teh ");
        compare(field.text, "the ");
    }

    function test_punctuationStartsANewWord() {
        type("(teh ");
        compare(field.text, "(the ");
        type("dont-teh:teh ");
        compare(field.text, "(the dont-teh:the ");
    }

    function test_autocorrectKeepsCapitals() {
        field.text = "Friday.";
        field.cursorPosition = field.text.length;
        tap(" teh ");
        compare(field.text, "Friday. The ");
        keyboard.handleShift();
        keyboard.handleShift();
        verify(keyboard.capsLock);
        tap("teh ");
        compare(field.text, "Friday. The THE ");
    }

    function test_autocorrectKeepsEarlierText() {
        field.text = "I said";
        field.cursorPosition = field.text.length;
        type(" teh ");
        compare(field.text, "I said the ");
    }

    function test_autocorrectSkipsWordTheFieldDoesNotHave() {
        type("teh");
        field.insert(field.cursorPosition, "s");
        type(" ");
        compare(field.text, "tehs ");
    }

    function test_autocorrectSkipsWordJoinedToEarlierText() {
        field.text = "x";
        field.cursorPosition = 1;
        type("teh ");
        compare(field.text, "xteh ");
    }

    function test_autocorrectSkipsAfterCursorMoved() {
        type("teh");
        field.cursorPosition = 0;
        type(" ");
        compare(field.text, " teh");
    }

    function test_autocorrectSkipsSelection() {
        type("teh");
        field.select(0, 3);
        type(" ");
        compare(field.text, " ");
    }

    function test_plainFieldIsNotCorrected() {
        keyboard.fieldHints = Qt.ImhNoPredictiveText;
        type("teh ");
        compare(field.text, "teh ");
    }

    function test_backspaceUndoesAutocorrect() {
        type("teh ");
        keyboard.handleBackspace();
        compare(field.text, "teh ");
        keyboard.handleBackspace();
        compare(field.text, "teh");
    }

    function test_undoLeavesChangedTextAlone() {
        type("teh ");
        field.insert(field.cursorPosition, "x");
        keyboard.handleBackspace();
        compare(field.text, "the ");
    }

    function test_doubleSpaceEndsSentence() {
        type("hello  ");
        compare(field.text, "hello. ");
        verify(keyboard.shifted);
    }

    function test_doubleSpaceAfterCorrection() {
        type("teh  ");
        compare(field.text, "the. ");
    }

    function test_doubleSpaceAfterPunctuationStaysSpaces() {
        type("hi.  ");
        compare(field.text, "hi.  ");
    }

    function test_slowSpacesStaySpaces() {
        type("hello ");
        pauseSpace();
        type(" ");
        compare(field.text, "hello  ");
    }

    function test_doubleSpaceOffWithoutAutoCapitals() {
        keyboard.fieldHints = Qt.ImhNoAutoUppercase;
        type("hello  ");
        compare(field.text, "hello  ");
    }

    function test_predictionReplacesWordAndAddsSpace() {
        field.text = "say";
        field.cursorPosition = 3;
        type(" hel");
        keyboard.acceptPrediction("hello");
        compare(field.text, "say hello ");
        compare(keyboard.currentWord, "");
    }

    function test_punctuationTakesThePredictionsSpace() {
        type("hel");
        keyboard.acceptPrediction("hello");
        type(",");
        compare(field.text, "hello, ");
        type("wor");
        keyboard.acceptPrediction("world");
        type(".");
        compare(field.text, "hello, world. ");
    }

    function test_letterKeepsThePredictionsSpace() {
        type("hel");
        keyboard.acceptPrediction("hello");
        type("w,");
        compare(field.text, "hello w,");
    }

    function test_predictionAfterSpaceIsInserted() {
        type("hi ");
        keyboard.acceptPrediction("there");
        compare(field.text, "hi there ");
    }

    function test_predictionOnlyCompletesWordTheFieldDoesNotHave() {
        field.text = "x";
        field.cursorPosition = 1;
        type("hel");
        keyboard.acceptPrediction("hello");
        compare(field.text, "xhello ");
    }

    function test_predictionLeavesWordItCannotReplace() {
        field.text = "x";
        field.cursorPosition = 1;
        type("teh");
        keyboard.acceptPrediction("the");
        compare(field.text, "xteh");
    }

    name: "MarathonKeyboard"
    when: windowShown

    Window {
        id: window

        width: 400
        height: 700
        visible: true

        TextInput {
            id: field

            width: parent.width
            height: 40
        }

        MarathonKeyboard {
            id: keyboard

            y: 60
            width: parent.width
        }
    }

    SignalSpy {
        id: acceptedSpy

        target: field
        signalName: "accepted"
    }
}
