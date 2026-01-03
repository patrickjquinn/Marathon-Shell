import QtQuick
import QtTest

TestCase {
    property string currentWord: ""
    property bool shifted: false
    property bool capsLock: false
    property var learnedWords: []
    property bool shouldAutoCapitalize: true
    property int enterEmits: 0

    function init() {
        currentWord = "";
        shifted = false;
        capsLock = false;
        learnedWords = [];
        shouldAutoCapitalize = true;
        enterEmits = 0;
    }

    function learnWord(word) {
        learnedWords.push(word);
    }

    function handleEnter() {
        if (currentWord.length > 0) {
            learnWord(currentWord);
            currentWord = "";
        }
        if (!capsLock && shouldAutoCapitalize)
            shifted = true;

        enterEmits++;
    }

    function test_handleEnter_learnsCurrentWord() {
        init();
        currentWord = "hello";
        handleEnter();
        compare(learnedWords.length, 1);
        compare(learnedWords[0], "hello");
    }

    function test_handleEnter_clearsCurrentWord() {
        init();
        currentWord = "test";
        handleEnter();
        compare(currentWord, "");
    }

    function test_handleEnter_setsShifted() {
        init();
        shifted = false;
        handleEnter();
        verify(shifted);
    }

    function test_handleEnter_capsLock_staysShifted() {
        init();
        capsLock = true;
        shifted = true;
        handleEnter();
        verify(shifted);
    }

    function test_handleEnter_noAutoCapitalize_noShift() {
        init();
        shouldAutoCapitalize = false;
        shifted = false;
        handleEnter();
        verify(!shifted);
    }

    function test_handleEnter_emptyWord_noLearn() {
        init();
        currentWord = "";
        handleEnter();
        compare(learnedWords.length, 0);
    }

    function test_handleEnter_emitsSignal() {
        init();
        handleEnter();
        compare(enterEmits, 1);
    }

    function test_handleEnter_multipleEnters() {
        init();
        currentWord = "test";
        handleEnter();
        currentWord = "again";
        handleEnter();
        compare(learnedWords.length, 2);
        compare(enterEmits, 2);
    }

    name: "EnterHandlingTests"
}
