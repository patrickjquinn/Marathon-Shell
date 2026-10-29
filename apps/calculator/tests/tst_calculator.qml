import QtQuick
import QtTest
import ".."

TestCase {
    name: "Calculator"

    Component {
        id: calcComponent
        Calculator {}
    }

    function make() {
        return createTemporaryObject(calcComponent, this);
    }

    function keys(c, seq) {
        for (const k of seq)
            c.press(k);
    }

    function test_startsAtZero() {
        const c = make();
        compare(c.displayText, "0");
        compare(c.history.length, 0);
    }

    function test_addition() {
        const c = make();
        keys(c, ["1", "2", "+", "3", "="]);
        compare(c.displayText, "15");
        compare(c.lastExpression, "12 + 3");
        compare(c.lastResult, "= 15");
    }

    function test_operators_data() {
        return [
            {
                tag: "minus",
                seq: ["9", "−", "4", "="],
                out: "5"
            },
            {
                tag: "times",
                seq: ["6", "×", "7", "="],
                out: "42"
            },
            {
                tag: "divide",
                seq: ["7", "÷", "2", "="],
                out: "3.5"
            },
            {
                tag: "mod",
                seq: ["7", "mod", "3", "="],
                out: "1"
            },
            {
                tag: "precedence",
                seq: ["2", "+", "3", "×", "4", "="],
                out: "14"
            },
            {
                tag: "times then plus",
                seq: ["2", "×", "3", "+", "4", "="],
                out: "10"
            },
            {
                tag: "two products",
                seq: ["2", "+", "3", "×", "4", "×", "5", "="],
                out: "62"
            },
            {
                tag: "product then minus",
                seq: ["2", "+", "3", "×", "4", "−", "1", "="],
                out: "13"
            },
            {
                tag: "minus then divide",
                seq: ["1", "0", "−", "6", "÷", "3", "="],
                out: "8"
            },
            {
                tag: "sqrt inside a product",
                seq: ["2", "+", "3", "×", "1", "6", "√", "="],
                out: "14"
            },
            {
                tag: "percent",
                seq: ["5", "0", "%"],
                out: "0.5"
            },
            {
                tag: "add percent",
                seq: ["5", "0", "+", "1", "0", "%", "="],
                out: "55"
            },
            {
                tag: "subtract percent",
                seq: ["8", "0", "−", "2", "5", "%", "="],
                out: "60"
            },
            {
                tag: "times percent",
                seq: ["5", "0", "×", "1", "0", "%", "="],
                out: "5"
            },
            {
                tag: "sign",
                seq: ["5", "+/−"],
                out: "-5"
            },
            {
                tag: "sqrt",
                seq: ["9", "√"],
                out: "3"
            },
            {
                tag: "square",
                seq: ["1", "2", "x²"],
                out: "144"
            },
            {
                tag: "factorial",
                seq: ["5", "!"],
                out: "120"
            },
            {
                tag: "sin",
                seq: ["9", "0", "sin"],
                out: "1"
            },
            {
                tag: "log",
                seq: ["1", "0", "0", "log"],
                out: "2"
            }
        ];
    }

    function test_operators(data) {
        const c = make();
        keys(c, data.seq);
        compare(c.displayText, data.out);
    }

    function test_precedenceShowsTheWholeExpression() {
        const c = make();
        keys(c, ["2", "+", "3", "×"]);
        compare(c.expressionText, "2 + 3 ×");
        keys(c, ["4", "="]);
        compare(c.lastExpression, "2 + 3 × 4");
        compare(c.history[c.history.length - 1].value, 14);
    }

    function test_undoRestoresThePendingSum() {
        const c = make();
        keys(c, ["2", "+", "3", "×"]);
        c.undo();
        compare(c.expressionText, "2 +");
    }

    function test_thousandsSeparators() {
        const c = make();
        keys(c, ["1", "2", "4", "8", "×", "7", "="]);
        compare(c.displayText, "8,736");
        compare(c.lastExpression, "1,248 × 7");
    }

    function test_formatsInTheUsersLocale() {
        const c = make();
        c.locale = Qt.locale("de_DE");
        keys(c, ["1", "2", "3", "4", ".", "5"]);
        compare(c.displayText, "1.234,5");
        keys(c, ["×", "1", "0", "0", "0", "="]);
        compare(c.displayText, "1.234.500");
    }

    function test_extremeValues() {
        const c = make();
        compare(c.fmt(0.1 + 0.2), "0.3");
        compare(c.fmt(1e-10), "1e-10");
        compare(c.fmt(0.000000123), "0.000000123");
        compare(c.fmt(1e21), "1e+21");
        compare(c.fmt(-2.5e16), "-2.5e+16");
        compare(c.fmt(123456789012), "123,456,789,012");
    }

    function test_entryKeepsTrailingDecimals() {
        const c = make();
        keys(c, ["1", ".", "5", "0"]);
        compare(c.displayText, "1.50");
        keys(c, ["."]);
        compare(c.displayText, "1.50");
    }

    function test_decimalStartsWithZero() {
        const c = make();
        c.press(".");
        compare(c.displayText, "0.");
    }

    function test_divideByZero() {
        const c = make();
        keys(c, ["5", "÷", "0", "="]);
        compare(c.errorText, "Can't divide by 0");
        compare(c.displayText, "Can't divide by 0");
        compare(c.history.length, 0);
        c.press("3");
        compare(c.errorText, "");
        compare(c.displayText, "3");
    }

    function test_invalidFactorialIsError() {
        const c = make();
        keys(c, ["2", ".", "5", "!"]);
        compare(c.errorText, "Error");
    }

    function test_backspace() {
        const c = make();
        keys(c, ["1", "2", "3", "⌫"]);
        compare(c.displayText, "12");
        keys(c, ["⌫", "⌫"]);
        compare(c.displayText, "0");
    }

    function test_backspaceIgnoresResult() {
        const c = make();
        keys(c, ["2", "×", "3", "=", "⌫"]);
        compare(c.displayText, "6");
    }

    function test_clearWipesEverything() {
        const c = make();
        keys(c, ["2", "+", "2", "=", "C"]);
        compare(c.displayText, "0");
        compare(c.lastExpression, "");
        compare(c.history.length, 0);
        verify(c.isClear);
    }

    function test_isClear() {
        const c = make();
        verify(c.isClear);
        c.press("7");
        verify(!c.isClear);
    }

    function test_historyNewestLastAndCapped() {
        const c = make();
        for (let i = 1; i <= 10; ++i)
            keys(c, [String(i % 10), "+", "1", "="]);
        compare(c.history.length, 8);
        compare(c.history[7].expression, "0 + 1");
        compare(c.history[7].result, "= 1");
    }

    function test_constantsAndAnswer() {
        const c = make();
        c.press("π");
        compare(c.displayText, "3.14159265359");
        c.press("e");
        compare(c.displayText, "2.71828182846");
        keys(c, ["C", "6", "×", "7", "=", "C", "ans"]);
        compare(c.displayText, "42");
    }

    function test_scientificKeepsPendingOperator() {
        const c = make();
        keys(c, ["2", "+", "9", "√", "="]);
        compare(c.displayText, "5");
    }

    function test_undo() {
        const c = make();
        verify(!c.canUndo);
        keys(c, ["4", "+", "1", "="]);
        verify(c.canUndo);
        c.undo();
        compare(c.displayText, "1");
        compare(c.history.length, 0);
        c.undo();
        c.undo();
        c.undo();
        compare(c.displayText, "0");
        verify(!c.canUndo);
    }

    function test_unknownKeyIgnored() {
        const c = make();
        c.press("q");
        compare(c.displayText, "0");
        verify(!c.canUndo);
    }

    function test_pendingOperatorIsShown() {
        const c = make();
        keys(c, ["7", "+"]);
        compare(c.expressionText, "7 +");
        keys(c, ["8", "="]);
        compare(c.expressionText, "7 + 8");
    }

    function test_paste_data() {
        return [
            {
                tag: "plain",
                text: "42",
                out: "42"
            },
            {
                tag: "trimmed",
                text: "  12.5\n",
                out: "12.5"
            },
            {
                tag: "grouped",
                text: "1,234,567",
                out: "1,234,567"
            },
            {
                tag: "spaces",
                text: "1 234 567",
                out: "1,234,567"
            },
            {
                tag: "decimal comma",
                text: "3,5",
                out: "3.5"
            },
            {
                tag: "european",
                text: "1.234,5",
                out: "1,234.5"
            },
            {
                tag: "english",
                text: "1,234.5",
                out: "1,234.5"
            },
            {
                tag: "negative",
                text: "-7",
                out: "-7"
            }
        ];
    }

    function test_paste(data) {
        const c = make();
        verify(c.paste(data.text));
        compare(c.displayText, data.out);
    }

    function test_pasteRejectsText() {
        const c = make();
        keys(c, ["5"]);
        verify(!c.paste("hello"));
        verify(!c.paste(""));
        verify(!c.paste("1.2.3,4,5"));
        compare(c.displayText, "5");
    }

    function test_pastedNumberIsAnOperand() {
        const c = make();
        keys(c, ["2", "+"]);
        c.paste("3");
        keys(c, ["="]);
        compare(c.displayText, "5");
    }
}
