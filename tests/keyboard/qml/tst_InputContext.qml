import QtQuick
import QtTest

TestCase {
    function test_textMode_autoCapitalize() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "text";
        verify(ctx.shouldAutoCapitalize === true);
    }

    function test_emailMode_noAutoCapitalize() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "email";
        verify(ctx.shouldAutoCapitalize === false);
    }

    function test_urlMode_noAutoCapitalize() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "url";
        verify(ctx.shouldAutoCapitalize === false);
    }

    function test_numberMode_noAutoCorrect() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "number";
        verify(ctx.shouldAutoCorrect === false);
    }

    function test_phoneMode_noPredictions() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "phone";
        verify(ctx.shouldShowPredictions === false);
    }

    function test_emailMode_showsPredictions() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "email";
        verify(ctx.shouldShowPredictions === true);
    }

    function test_insertText_emitsSignal() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        var spy = createTemporaryObject(signalSpyComponent, this, {
            "target": ctx,
            "signalName": "textInserted"
        });
        ctx.insertText("hello");
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "hello");
    }

    function test_handleBackspace_emitsSignal() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        var spy = createTemporaryObject(signalSpyComponent, this, {
            "target": ctx,
            "signalName": "backspacePressed"
        });
        ctx.handleBackspace();
        compare(spy.count, 1);
    }

    function test_handleEnter_emitsSignal() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        var spy = createTemporaryObject(signalSpyComponent, this, {
            "target": ctx,
            "signalName": "enterPressed"
        });
        ctx.handleEnter();
        compare(spy.count, 1);
    }

    function test_terminalMode_noAutoCapitalize() {
        var ctx = createTemporaryObject(inputContextComponent, this);
        ctx.inputMode = "terminal";
        verify(ctx.shouldAutoCapitalize === false);
        verify(ctx.shouldAutoCorrect === false);
        verify(ctx.shouldShowPredictions === false);
    }

    name: "InputContextTests"

    Component {
        id: inputContextComponent

        Item {
            id: wrapper

            property string inputMode: "text"
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

            function insertText(text) {
                textInserted(text);
            }

            function handleBackspace() {
                backspacePressed();
            }

            function handleEnter() {
                enterPressed();
            }
        }
    }

    Component {
        id: signalSpyComponent

        SignalSpy {}
    }
}
