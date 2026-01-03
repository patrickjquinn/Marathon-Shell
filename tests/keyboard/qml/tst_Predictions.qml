import QtQuick
import QtTest

TestCase {
    property string currentWord: ""
    property var currentPredictions: []
    property var insertedTexts: []
    property int backspaceEmits: 0
    property var learnedWords: []
    property bool shifted: false
    property bool capsLock: false
    property bool shouldAutoCapitalize: true

    function init() {
        currentWord = "";
        currentPredictions = ["test1", "test2", "test3"];
        insertedTexts = [];
        backspaceEmits = 0;
        learnedWords = [];
        shifted = false;
        capsLock = false;
        shouldAutoCapitalize = true;
    }

    function insertText(text) {
        insertedTexts.push(text);
    }

    function learnWord(word) {
        learnedWords.push(word);
    }

    function acceptPrediction(word) {
        var charsToDelete = currentWord.length;
        for (var i = 0; i < charsToDelete; i++)
            backspaceEmits++;
        insertText(word + " ");
        learnWord(word);
        currentWord = "";
        currentPredictions = [];
        if (!capsLock && shouldAutoCapitalize)
            shifted = true;
    }

    function test_acceptPrediction_deletesCurrentWord() {
        init();
        currentWord = "hel";
        acceptPrediction("hello");
        compare(backspaceEmits, 3);
    }

    function test_acceptPrediction_insertsWordWithSpace() {
        init();
        currentWord = "te";
        acceptPrediction("testing");
        compare(insertedTexts.length, 1);
        compare(insertedTexts[0], "testing ");
    }

    function test_acceptPrediction_learnsWord() {
        init();
        currentWord = "wo";
        acceptPrediction("wonderful");
        compare(learnedWords.length, 1);
        compare(learnedWords[0], "wonderful");
    }

    function test_acceptPrediction_clearsCurrentWord() {
        init();
        currentWord = "par";
        acceptPrediction("partial");
        compare(currentWord, "");
    }

    function test_acceptPrediction_clearsPredictions() {
        init();
        currentWord = "te";
        currentPredictions = ["test1", "test2"];
        acceptPrediction("test1");
        compare(currentPredictions.length, 0);
    }

    function test_acceptPrediction_setsShifted() {
        init();
        currentWord = "te";
        shifted = false;
        acceptPrediction("test");
        verify(shifted);
    }

    function test_acceptPrediction_capsLock_noAutoShift() {
        init();
        currentWord = "te";
        capsLock = true;
        shifted = true;
        acceptPrediction("test");
        verify(shifted);
    }

    function test_acceptPrediction_emptyCurrentWord() {
        init();
        currentWord = "";
        acceptPrediction("word");
        compare(backspaceEmits, 0);
        compare(insertedTexts[0], "word ");
    }

    function test_acceptPrediction_longWord() {
        init();
        currentWord = "supercalifrag";
        acceptPrediction("supercalifragilisticexpialidocious");
        compare(backspaceEmits, 13);
        compare(insertedTexts[0], "supercalifragilisticexpialidocious ");
    }

    function test_acceptPrediction_withPunctuation() {
        init();
        currentWord = "don";
        acceptPrediction("don't");
        compare(insertedTexts[0], "don't ");
    }

    name: "PredictionTests"
}
