import QtQuick
import QtTest

TestCase {
    property string currentWord: ""
    property bool shifted: false
    property bool capsLock: false
    property var currentPredictions: []
    property real lastSpaceTime: 0
    property real lastShiftTime: 0
    readonly property string sentenceEndingPunctuation: "!.?"

    function init() {
        currentWord = "";
        shifted = false;
        capsLock = false;
        currentPredictions = [];
        lastSpaceTime = 0;
        lastShiftTime = 0;
    }

    function handleKeyPress(text) {
        currentWord += text;
        if (sentenceEndingPunctuation.indexOf(text) !== -1) {
            if (!capsLock) {
                shifted = true;
                currentWord = "";
            }
            return;
        }
        if (text === ",")
            currentWord = "";

        if (shifted && !capsLock)
            shifted = false;
    }

    function handleBackspace() {
        if (currentWord.length > 0) {
            currentWord = currentWord.slice(0, -1);
            if (currentWord.length === 0)
                currentPredictions = [];
        }
    }

    function handleShift() {
        var now = Date.now();
        var isDoubleTap = (now - lastShiftTime < 300);
        if (capsLock) {
            capsLock = false;
            shifted = false;
        } else if (isDoubleTap && shifted) {
            capsLock = true;
            shifted = true;
        } else {
            shifted = !shifted;
        }
        lastShiftTime = now;
    }

    function test_handleKeyPress_addsToCurrentWord() {
        init();
        handleKeyPress("h");
        handleKeyPress("e");
        handleKeyPress("l");
        compare(currentWord, "hel");
    }

    function test_handleKeyPress_period_clearsWord() {
        init();
        currentWord = "hello";
        handleKeyPress(".");
        compare(currentWord, "");
        verify(shifted);
    }

    function test_handleKeyPress_questionMark_triggersShift() {
        init();
        currentWord = "what";
        handleKeyPress("?");
        compare(currentWord, "");
        verify(shifted);
    }

    function test_handleKeyPress_exclamation_triggersShift() {
        init();
        currentWord = "wow";
        handleKeyPress("!");
        compare(currentWord, "");
        verify(shifted);
    }

    function test_handleKeyPress_comma_clearsWord() {
        init();
        currentWord = "hello";
        handleKeyPress(",");
        compare(currentWord, "");
    }

    function test_handleBackspace_removesLastChar() {
        init();
        currentWord = "hello";
        handleBackspace();
        compare(currentWord, "hell");
    }

    function test_handleBackspace_clearsPredictionsWhenEmpty() {
        init();
        currentWord = "a";
        currentPredictions = ["apple", "ant"];
        handleBackspace();
        compare(currentWord, "");
        compare(currentPredictions.length, 0);
    }

    function test_handleBackspace_emptyWord_noChange() {
        init();
        currentWord = "";
        handleBackspace();
        compare(currentWord, "");
    }

    function test_handleShift_togglesShift() {
        init();
        verify(!shifted);
        handleShift();
        verify(shifted);
    }

    function test_handleShift_doubleTap_enablesCapsLock() {
        init();
        handleShift();
        verify(shifted);
        lastShiftTime = Date.now();
        handleShift();
        verify(capsLock);
        verify(shifted);
    }

    function test_handleShift_capsLock_disables() {
        init();
        capsLock = true;
        shifted = true;
        handleShift();
        verify(!capsLock);
        verify(!shifted);
    }

    function test_shiftAutoDisables_afterKeyPress() {
        init();
        shifted = true;
        capsLock = false;
        handleKeyPress("A");
        verify(!shifted);
    }

    function test_capsLock_staysShifted() {
        init();
        shifted = true;
        capsLock = true;
        handleKeyPress("A");
        verify(shifted);
    }

    function test_multipleChars_buildsWord() {
        init();
        var word = "testing";
        for (var i = 0; i < word.length; i++)
            handleKeyPress(word[i]);
        compare(currentWord, "testing");
    }

    name: "KeyboardCoreTests"
}
