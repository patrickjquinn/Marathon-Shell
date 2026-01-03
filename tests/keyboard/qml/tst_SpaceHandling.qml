import QtQuick
import QtTest

TestCase {
    property string currentWord: ""
    property bool shifted: false
    property bool capsLock: false
    property real lastSpaceTime: 0
    property var insertedTexts: []
    property int backspaceCount: 0
    property bool shouldAutoCapitalize: true

    function init() {
        currentWord = "";
        shifted = false;
        capsLock = false;
        lastSpaceTime = 0;
        insertedTexts = [];
        backspaceCount = 0;
        shouldAutoCapitalize = true;
    }

    function insertText(text) {
        insertedTexts.push(text);
    }

    function handleBackspace() {
        backspaceCount++;
    }

    function handleSpace() {
        var now = Date.now();
        var isDoubleTap = (now - lastSpaceTime < 300) && currentWord.length === 0;
        if (isDoubleTap && shouldAutoCapitalize) {
            handleBackspace();
            insertText(". ");
            shifted = true;
            lastSpaceTime = 0;
            return;
        }
        if (currentWord.length > 0)
            currentWord = "";

        if (!capsLock && shouldAutoCapitalize)
            shifted = true;

        insertText(" ");
        lastSpaceTime = now;
    }

    function test_handleSpace_insertsSpace() {
        init();
        handleSpace();
        compare(insertedTexts.length, 1);
        compare(insertedTexts[0], " ");
    }

    function test_handleSpace_clearsCurrentWord() {
        init();
        currentWord = "hello";
        handleSpace();
        compare(currentWord, "");
    }

    function test_handleSpace_setsShifted() {
        init();
        shifted = false;
        shouldAutoCapitalize = true;
        handleSpace();
        verify(shifted);
    }

    function test_handleSpace_capsLock_noAutoShift() {
        init();
        capsLock = true;
        shifted = true;
        handleSpace();
        verify(shifted);
    }

    function test_handleSpace_doubleTap_createsPeriod() {
        init();
        handleSpace();
        compare(insertedTexts[0], " ");
        handleSpace();
        compare(insertedTexts.length, 2);
        compare(backspaceCount, 1);
        compare(insertedTexts[1], ". ");
        verify(shifted);
    }

    function test_handleSpace_noAutoCapitalize_noShift() {
        init();
        shouldAutoCapitalize = false;
        shifted = false;
        handleSpace();
        verify(!shifted);
    }

    function test_handleSpace_updatesLastSpaceTime() {
        init();
        compare(lastSpaceTime, 0);
        handleSpace();
        verify(lastSpaceTime > 0);
    }

    function test_handleSpace_tripleSpace_onlyOnePeriod() {
        init();
        handleSpace();
        handleSpace();
        handleSpace();
        compare(insertedTexts.filter(function (t) {
            return t === ". ";
        }).length, 1);
    }

    name: "SpaceHandlingTests"
}
