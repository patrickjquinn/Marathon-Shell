import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."
import "../cover"

TestCase {
    name: "CalculatorCover"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component { id: coverComponent; CalculatorCover { calc: Calculator {} } }

    function make() {
        const cover = createTemporaryObject(coverComponent, this);
        return { calc: cover.calc, cover: cover };
    }

    function test_showsResultAndExpression() {
        const t = make();
        for (const k of ["6", "×", "7", "="])
            t.calc.press(k);
        compare(findChild(t.cover, "coverValue").text, "42");
        compare(findChild(t.cover, "coverExpression").text, "6 × 7");
    }

    function test_followsTyping() {
        const t = make();
        t.calc.press("9");
        t.calc.press(".");
        compare(findChild(t.cover, "coverValue").text, "9.");
    }

    function test_showsPendingOperation() {
        const t = make();
        for (const k of ["6", "×", "7", "=", "+", "3"])
            t.calc.press(k);
        compare(findChild(t.cover, "coverExpression").text, "42 +");
        compare(findChild(t.cover, "coverValue").text, "3");
    }

    function test_showsErrors() {
        const t = make();
        for (const k of ["1", "÷", "0", "="])
            t.calc.press(k);
        compare(findChild(t.cover, "coverValue").text, "Can't divide by 0");
    }

    function test_clearAction() {
        const t = make();
        t.calc.press("5");
        findChild(t.cover, "clearAction").triggered();
        verify(t.calc.isClear);
    }
}
