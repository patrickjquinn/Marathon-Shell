import QtQuick
import QtTest

TestCase {
    property string currentWord: ""
    property string lastCorrectedWord: ""
    property string lastOriginalWord: ""
    property bool canUndoAutoCorrect: false
    property var insertedTexts: []
    property int backspaceCount: 0

    function init() {
        currentWord = "";
        lastCorrectedWord = "";
        lastOriginalWord = "";
        canUndoAutoCorrect = false;
        insertedTexts = [];
        backspaceCount = 0;
    }

    function insertText(text) {
        insertedTexts.push(text);
    }

    function handleBackspaceAction() {
        backspaceCount++;
    }

    function handleSpace_withCorrection(originalWord, correctedWord) {
        if (correctedWord !== originalWord) {
            lastOriginalWord = originalWord;
            lastCorrectedWord = correctedWord;
            canUndoAutoCorrect = true;
        } else {
            canUndoAutoCorrect = false;
        }
        currentWord = "";
        insertText(" ");
    }

    function handleBackspace() {
        if (canUndoAutoCorrect && currentWord.length === 0) {
            var correctedLen = lastCorrectedWord.length + 1;
            for (var i = 0; i < correctedLen; i++) {
                handleBackspaceAction();
            }
            insertText(lastOriginalWord + " ");
            canUndoAutoCorrect = false;
            lastOriginalWord = "";
            lastCorrectedWord = "";
            return true;
        }
        canUndoAutoCorrect = false;
        handleBackspaceAction();
        if (currentWord.length > 0)
            currentWord = currentWord.slice(0, -1);

        return false;
    }

    function test_undoAutoCorrect_enabled_afterCorrection() {
        init();
        handleSpace_withCorrection("teh", "the");
        verify(canUndoAutoCorrect, "Undo should be enabled after correction");
        compare(lastOriginalWord, "teh");
        compare(lastCorrectedWord, "the");
    }

    function test_undoAutoCorrect_disabled_noCorrection() {
        init();
        handleSpace_withCorrection("hello", "hello");
        verify(!canUndoAutoCorrect, "Undo should be disabled when no correction");
    }

    function test_undoAutoCorrect_backspace_revertsCorrection() {
        init();
        handleSpace_withCorrection("teh", "the");
        compare(insertedTexts.length, 1);
        compare(insertedTexts[0], " ");
        var undone = handleBackspace();
        verify(undone, "Should indicate undo happened");
        compare(backspaceCount, 4, "Should delete 'the ' (4 chars)");
        compare(insertedTexts.length, 2);
        compare(insertedTexts[1], "teh ", "Should re-insert original with space");
        verify(!canUndoAutoCorrect, "Undo should be disabled after use");
    }

    function test_undoAutoCorrect_disabledAfterTyping() {
        init();
        handleSpace_withCorrection("teh", "the");
        verify(canUndoAutoCorrect);
        currentWord = "n";
        var undone = handleBackspace();
        verify(!undone, "Should not undo when in new word");
        verify(!canUndoAutoCorrect, "Undo should be disabled");
    }

    function test_undoAutoCorrect_clearsState() {
        init();
        handleSpace_withCorrection("teh", "the");
        handleBackspace();
        compare(lastOriginalWord, "");
        compare(lastCorrectedWord, "");
    }

    function test_normalBackspace_decrementWord() {
        init();
        currentWord = "hello";
        handleBackspace();
        compare(currentWord, "hell");
    }

    name: "UndoAutoCorrectTests"
}
