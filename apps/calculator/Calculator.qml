import QtQml

QtObject {
    id: calc

    property string display: "0"
    property string lastExpression: ""
    property string lastResult: ""
    property real currentValue: 0
    property string currentOperator: ""
    property bool newNumber: true
    property string errorText: ""
    property var history: []
    property real lastAnswer: 0
    property var undoStack: []

    readonly property bool canUndo: undoStack.length > 0
    readonly property bool isClear: display === "0" && newNumber && lastExpression === "" && errorText === ""
                                    && currentOperator === "" && history.length === 0
    readonly property string displayText: errorText !== "" ? errorText
                                          : newNumber ? fmt(parseFloat(display)) : fmtEntry(display)
    readonly property string expressionText: currentOperator !== "" ? fmt(currentValue) + " " + currentOperator
                                             : lastExpression

    readonly property var keys: ["C", "⌫", "%", "÷", "×", "−", "+", "+/−", ".", "=",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "mod", "π", "e", "√", "x²", "sin", "cos", "tan", "log", "ln", "!", "ans"]

    function fmt(n) {
        const fixed = Number(n).toFixed(8);
        const trimmed = fixed.indexOf(".") >= 0 ? fixed.replace(/\.?0+$/, "") : fixed;
        const parts = trimmed.split(".");
        const intPart = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return parts.length > 1 ? intPart + "." + parts[1] : intPart;
    }

    // Formats the number being typed without parsing it, so "0." and "1.50" stay visible.
    function fmtEntry(s) {
        const dot = s.indexOf(".");
        const intPart = (dot >= 0 ? s.substring(0, dot) : s).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return dot >= 0 ? intPart + s.substring(dot) : intPart;
    }

    // "," or "." is the decimal mark; a lone separator before exactly three digits groups.
    function parseNumber(text) {
        const m = /^(-?)([\d.,]+)$/.exec(String(text).trim().replace(/[\s\u00a0\u202f']/g, ""));
        if (!m)
            return NaN;
        const body = m[2];
        const last = Math.max(body.lastIndexOf("."), body.lastIndexOf(","));
        const sep = body.charAt(last);
        const other = sep === "." ? "," : ".";
        const decimal = last >= 0 && (body.indexOf(other) >= 0
                                      || (body.indexOf(sep) === last && body.length - last - 1 !== 3));
        const whole = decimal ? body.substring(0, last) : body;
        const frac = decimal ? body.substring(last + 1) : "";
        const group = decimal ? other : sep;
        if (group !== "" && whole.indexOf(group) >= 0 && !new RegExp("^\\d{1,3}(\\" + group + "\\d{3})+$").test(whole))
            return NaN;
        const digits = group === "" ? whole : whole.split(group).join("");
        if (!/^\d*$/.test(digits) || !/^\d*$/.test(frac) || digits + frac === "")
            return NaN;
        return parseFloat(m[1] + (digits || "0") + "." + (frac || "0"));
    }

    function paste(text) {
        const n = parseNumber(text);
        if (!isFinite(n))
            return false;
        snapshot();
        errorText = "";
        display = String(n);
        newNumber = true;
        return true;
    }

    function press(k) {
        if (keys.indexOf(k) === -1)
            return;
        snapshot();
        if (k === "C")
            clear();
        else if (k === "=")
            calculate();
        else if (k === "+/−")
            toggleSign();
        else if (k === ".")
            appendDecimal();
        else if (k === "⌫")
            backspace();
        else if (k === "%")
            applyScientific("percent");
        else if ("+−×÷".indexOf(k) !== -1 || k === "mod")
            setOperator(k);
        else if ("0123456789".indexOf(k) !== -1)
            appendDigit(k);
        else if (k === "π")
            insertConstant(Math.PI);
        else if (k === "e")
            insertConstant(Math.E);
        else if (k === "√")
            applyScientific("sqrt");
        else if (k === "x²")
            applyScientific("sq");
        else if (k === "!")
            applyScientific("fact");
        else if (k === "ans")
            recallAnswer();
        else
            applyScientific(k);
    }

    function snapshot() {
        const next = undoStack.slice();
        next.push({
            "display": display,
            "lastExpression": lastExpression,
            "lastResult": lastResult,
            "currentValue": currentValue,
            "currentOperator": currentOperator,
            "newNumber": newNumber,
            "errorText": errorText,
            "history": history,
            "lastAnswer": lastAnswer
        });
        if (next.length > 50)
            next.shift();
        undoStack = next;
    }

    function undo() {
        if (undoStack.length === 0)
            return;
        const next = undoStack.slice();
        const s = next.pop();
        undoStack = next;
        display = s.display;
        lastExpression = s.lastExpression;
        lastResult = s.lastResult;
        currentValue = s.currentValue;
        currentOperator = s.currentOperator;
        newNumber = s.newNumber;
        errorText = s.errorText;
        history = s.history;
        lastAnswer = s.lastAnswer;
    }

    function setResult(expr, r, divideByZero) {
        lastExpression = expr;
        newNumber = true;
        currentOperator = "";
        if (divideByZero || !isFinite(r)) {
            errorText = divideByZero ? qsTr("Can't divide by 0") : qsTr("Error");
            lastResult = "";
            display = "0";
            return;
        }
        lastResult = "= " + fmt(r);
        lastAnswer = r;
        display = String(r);
    }

    function appendDigit(digit) {
        errorText = "";
        if (newNumber) {
            display = digit;
            newNumber = false;
        } else {
            display = display === "0" ? digit : display + digit;
        }
    }

    function appendDecimal() {
        errorText = "";
        if (newNumber) {
            display = "0.";
            newNumber = false;
        } else if (display.indexOf(".") === -1) {
            display += ".";
        }
    }

    function toggleSign() {
        if (display.charAt(0) === "-")
            display = display.substring(1);
        else if (display !== "0")
            display = "-" + display;
    }

    function setOperator(op) {
        if (currentOperator !== "" && !newNumber)
            calculate();
        if (errorText !== "")
            return;
        currentValue = parseFloat(display);
        currentOperator = op;
        newNumber = true;
    }

    function calculate() {
        if (currentOperator === "")
            return;
        const value = parseFloat(display);
        let result = currentValue;
        switch (currentOperator) {
        case "+":
            result = currentValue + value;
            break;
        case "−":
            result = currentValue - value;
            break;
        case "×":
            result = currentValue * value;
            break;
        case "÷":
            result = currentValue / value;
            break;
        case "mod":
            result = currentValue % value;
            break;
        }
        const expr = fmt(currentValue) + " " + currentOperator + " " + fmt(value);
        setResult(expr, result, value === 0 && (currentOperator === "÷" || currentOperator === "mod"));
        if (errorText !== "")
            return;
        const next = history.slice();
        next.push({
            "expression": lastExpression,
            "result": lastResult
        });
        if (next.length > 8)
            next.shift();
        history = next;
    }

    function clear() {
        display = "0";
        lastExpression = "";
        lastResult = "";
        errorText = "";
        history = [];
        currentValue = 0;
        currentOperator = "";
        newNumber = true;
    }

    function factorial(n) {
        if (n < 0 || Math.floor(n) !== n || n > 170)
            return NaN;
        let f = 1;
        for (let i = 2; i <= n; i++)
            f *= i;
        return f;
    }

    // Trig is in degrees.
    function applyScientific(name) {
        if (errorText !== "")
            return;
        const x = parseFloat(display);
        let r = x;
        let expr = "";
        switch (name) {
        case "sqrt":    r = Math.sqrt(x);                expr = "√(" + fmt(x) + ")"; break;
        case "sq":      r = x * x;                       expr = fmt(x) + "²"; break;
        case "sin":     r = Math.sin(x * Math.PI / 180); expr = "sin(" + fmt(x) + "°)"; break;
        case "cos":     r = Math.cos(x * Math.PI / 180); expr = "cos(" + fmt(x) + "°)"; break;
        case "tan":     r = Math.tan(x * Math.PI / 180); expr = "tan(" + fmt(x) + "°)"; break;
        case "log":     r = Math.log(x) / Math.LN10;     expr = "log(" + fmt(x) + ")"; break;
        case "ln":      r = Math.log(x);                 expr = "ln(" + fmt(x) + ")"; break;
        case "fact":    r = factorial(x);                expr = fmt(x) + "!"; break;
        case "percent": r = x / 100;                     expr = fmt(x) + "%"; break;
        default: return;
        }
        const pending = currentOperator;
        setResult(expr, r, false);
        if (errorText === "")
            currentOperator = pending;
    }

    function insertConstant(v) {
        errorText = "";
        display = String(v);
        newNumber = true;
    }

    function recallAnswer() {
        errorText = "";
        display = String(lastAnswer);
        newNumber = true;
    }

    function backspace() {
        if (newNumber)
            return;
        const negativeSingle = display.length === 2 && display.charAt(0) === "-";
        if (display.length <= 1 || negativeSingle) {
            display = "0";
            newNumber = true;
        } else {
            display = display.slice(0, -1);
        }
    }
}
