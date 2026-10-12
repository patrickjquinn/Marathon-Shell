pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Calculator (screens-apps-2.jsx:CalculatorApp).
//
// Top bar: Undo · Basic/Scientific toggle.
// Display: right-aligned column — prior expression (small / tertiary),
// "= preview" (teal-bright), final Display-weight result.
// Scientific mode adds a scrollable function chip row (mod · π · √ · x² · sin …).
// 4 × 5 keypad — rounded-square elev-2 buttons with w-04 border:
//   row 1 ⬢ C  · ⌫   · %  · ÷       (ops in teal-bright)
//   row 2 ⬢ 7  · 8   · 9  · ×
//   row 3 ⬢ 4  · 5   · 6  · −
//   row 4 ⬢ 1  · 2   · 3  · +
//   row 5 ⬢ ±  · 0   · .  · =       (= is a teal-gradient pill with glow)
MApp {
    id: calcApp

    property string display: "0"
    property string lastExpression: ""        // "1,248 × 7" style preview line
    property string lastResult: ""            // "= 8,736" preview line
    property real currentValue: 0
    property string currentOperator: ""
    property bool newNumber: true
    // Set when the last operation had no real answer; shown in place of the number.
    property string errorText: ""
    property bool scientific: true
    // Recent expressions, oldest first. Capped at 8 to bound memory and to
    // keep the on-screen history list short enough to read at a glance.
    property var history: []
    // Last computed result, kept as a real number (not the formatted
    // lastResult text) so the "ans" key round-trips exactly.
    property real lastAnswer: 0
    property var undoStack: []

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
            errorText = divideByZero ? "Can't divide by 0" : "Error";
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
        // Reassigning (not .push) is what makes QML notice historyChanged.
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
            return NaN;              // negative/non-integer undefined; >170! overflows a double
        let f = 1;
        for (let i = 2; i <= n; i++)
            f *= i;
        return f;
    }

    // Immediate-execution scientific ops on the current display value. Trig is in degrees.
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

    appId: "calculator"
    appName: "Calculator"
    appIcon: "assets/icon.svg"

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        // ── Top bar — Undo · Basic/Scientific ───────────────
        Item {
            id: topBar
            width: parent.width
            height: MSpacing.touchTargetSmall
            anchors.top: parent.top

            Item {
                anchors.left: parent.left
                anchors.leftMargin: MSpacing.sm
                anchors.verticalCenter: parent.verticalCenter
                width: undoRow.implicitWidth + MSpacing.md
                height: MSpacing.touchTargetMin
                opacity: calcApp.undoStack.length > 0 ? 1 : 0.4

                Accessible.role: Accessible.Button
                Accessible.name: "Undo"
                Accessible.onPressAction: calcApp.undo()

                Row {
                    id: undoRow
                    anchors.centerIn: parent
                    spacing: MSpacing.xs
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "undo-2"
                        size: 18
                        color: MColors.textSecondary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Undo"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: calcApp.undoStack.length > 0
                    onClicked: {
                        HapticService.light();
                        calcApp.undo();
                    }
                }
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: modeRow.implicitWidth + MSpacing.md * 2
                height: MSpacing.touchTargetMin

                Accessible.role: Accessible.Button
                Accessible.name: calcApp.scientific ? "Switch to basic mode" : "Switch to scientific mode"
                Accessible.onPressAction: calcApp.scientific = !calcApp.scientific

                Row {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: MSpacing.xs
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: calcApp.scientific ? "Scientific" : "Basic"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeSubhead
                        font.weight: Font.Medium
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrows-left-right"
                        size: 16
                        color: MColors.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        calcApp.scientific = !calcApp.scientific;
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: MColors.whiteOverlay04
            }
        }

        // ── Expression history ─────────────────────────────
        // Fills the gap between the top bar and the bottom-anchored
        // display column with prior calculations, oldest at top.
        // Newest sticks to the bottom (verticalLayoutDirection)
        // so it reads as a paper-tape descending into the current
        // result without an explicit positionViewAt call.
        ListView {
            id: historyList
            anchors.top: topBar.bottom
            anchors.bottom: displayCol.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            verticalLayoutDirection: ListView.BottomToTop
            clip: true
            spacing: 6
            model: calcApp.history

            delegate: Column {
                id: historyEntry

                required property var modelData

                width: ListView.view.width
                spacing: 1
                Text {
                    anchors.right: parent.right
                    text: historyEntry.modelData.expression
                    color: MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.features: ({
                            "tnum": 1
                        })
                }
                Text {
                    anchors.right: parent.right
                    text: historyEntry.modelData.result
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    font.weight: Font.Medium
                    font.features: ({
                            "tnum": 1
                        })
                }
            }
        }

        // Empty-state hint when history hasn't been populated yet.
        // The historyList occupies ~700 design-px between the top bar
        // and the result column; first-launch users saw that gap as
        // an unstyled void. A faint two-line glyph + caption makes it
        // read as a tape that's just waiting for input.
        //
        // Tied to historyList's exact anchor frame so it lives in the
        // same dead zone — no double-positioning math elsewhere.
        Item {
            anchors.fill: historyList
            visible: calcApp.history.length === 0

            Column {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "="
                    color: MColors.textTertiary
                    opacity: 0.4
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeTitle1
                    font.weight: MTypography.weightThin
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Your calculations will appear here"
                    color: MColors.textTertiary
                    opacity: 0.6
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                }
            }
        }

        // ── Display — right-aligned column ──────────────────
        // Anchor BOTTOM to the function-chip row instead of TOP to the
        // app-bar. iOS Calculator positions the digits flush against the
        // keypad so the display "grows up" as the user types; the
        // previous top-anchored layout pinned "0" at the top of the
        // surface and left a ~750 px void between the digit and the
        // keypad. The Column packs from top still, but its top edge is
        // pushed down because we anchor the bottom; the result is the
        // display tracking the keypad's edge instead of floating.
        Column {
            id: displayCol
            anchors.bottom: calcApp.scientific ? fnRow.top : keypad.top
            anchors.bottomMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 4

            Text {
                anchors.right: parent.right
                text: calcApp.lastExpression
                color: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: Font.Normal
                visible: text.length > 0
                font.features: ({
                        "tnum": 1
                    })
            }
            Text {
                anchors.right: parent.right
                text: calcApp.lastResult
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: Font.Medium
                visible: text.length > 0
                font.features: ({
                        "tnum": 1
                    })
            }
            Text {
                anchors.right: parent.right
                text: calcApp.errorText !== "" ? calcApp.errorText : calcApp.newNumber ? calcApp.fmt(parseFloat(calcApp.display)) : calcApp.fmtEntry(calcApp.display)
                color: calcApp.errorText !== "" ? MColors.error : MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: calcApp.errorText !== "" ? MTypography.sizeTitle1 : 64
                font.weight: MTypography.weightExtraLight   // 200 per DS Display
                font.letterSpacing: -1.5
                font.features: ({
                        "tnum": 1
                    })
                elide: Text.ElideLeft
                width: parent.width
                horizontalAlignment: Text.AlignRight
            }
        }

        // ── Function chip row (scrollable) ──────────────────
        ListView {
            id: fnRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: keypad.top
            anchors.bottomMargin: 12
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: MSpacing.touchTargetMin
            visible: calcApp.scientific
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            model: ["mod", "π", "√", "x²", "sin", "cos", "tan", "log", "ln", "!", "ans"]
            delegate: Rectangle {
                id: chip

                required property var modelData

                width: Math.round(56 * Constants.scaleFactor)
                height: MSpacing.touchTargetMin
                radius: MRadius.md
                Accessible.role: Accessible.Button
                Accessible.name: ({
                        "mod": "Modulo",
                        "π": "Pi",
                        "√": "Square root",
                        "x²": "Square",
                        "sin": "Sine",
                        "cos": "Cosine",
                        "tan": "Tangent",
                        "log": "Logarithm",
                        "ln": "Natural logarithm",
                        "!": "Factorial",
                        "ans": "Last answer"
                    })[modelData]
                Accessible.onPressAction: chipArea.clicked(null)
                color: chipArea.pressed ? MColors.bb10Card : "transparent"
                border.width: 1
                border.color: MColors.whiteOverlay08
                Text {
                    anchors.centerIn: parent
                    text: chip.modelData
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.weight: Font.Medium
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        calcApp.snapshot();
                        const k = chip.modelData;
                        if (k === "mod")
                            calcApp.setOperator("mod");     // binary — completes on "="
                        else if (k === "π")
                            calcApp.insertConstant(Math.PI);
                        else if (k === "√")
                            calcApp.applyScientific("sqrt");
                        else if (k === "x²")
                            calcApp.applyScientific("sq");
                        else if (k === "!")
                            calcApp.applyScientific("fact");
                        else if (k === "ans")
                            calcApp.recallAnswer();
                        else
                            calcApp.applyScientific(k);     // sin/cos/tan/log/ln
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.micro
                    }
                }
            }
        }

        // ── 4 × 5 keypad ────────────────────────────────────
        Grid {
            id: keypad
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 12
            columns: 4
            rowSpacing: 8
            columnSpacing: 8

            property real cellW: (width - 3 * columnSpacing) / 4
            property real cellH: Math.min(cellW, 70)

            Repeater {
                model: [
                    {
                        k: "C",
                        type: "op-soft"
                    },
                    {
                        k: "⌫",
                        type: "op-soft"
                    },
                    {
                        k: "%",
                        type: "op-soft"
                    },
                    {
                        k: "÷",
                        type: "op"
                    },
                    {
                        k: "7",
                        type: "digit"
                    },
                    {
                        k: "8",
                        type: "digit"
                    },
                    {
                        k: "9",
                        type: "digit"
                    },
                    {
                        k: "×",
                        type: "op"
                    },
                    {
                        k: "4",
                        type: "digit"
                    },
                    {
                        k: "5",
                        type: "digit"
                    },
                    {
                        k: "6",
                        type: "digit"
                    },
                    {
                        k: "−",
                        type: "op"
                    },
                    {
                        k: "1",
                        type: "digit"
                    },
                    {
                        k: "2",
                        type: "digit"
                    },
                    {
                        k: "3",
                        type: "digit"
                    },
                    {
                        k: "+",
                        type: "op"
                    },
                    {
                        k: "+/−",
                        type: "op-soft"
                    },
                    {
                        k: "0",
                        type: "digit"
                    },
                    {
                        k: ".",
                        type: "digit"
                    },
                    {
                        k: "=",
                        type: "primary"
                    }
                ]

                Rectangle {
                    id: key

                    required property var modelData

                    width: keypad.cellW
                    height: keypad.cellH
                    radius: MRadius.md

                    color: {
                        if (modelData.type === "primary")
                            return "transparent"; // gradient
                        if (keyArea.pressed)
                            return MColors.bb10Card;
                        // elev-1 over bb10Black gave the chip 6 brightness
                        // units of separation from the canvas — visually the
                        // chrome disappeared and the numbers floated. elev-2
                        // restores the puck silhouette without darkening the
                        // primary "=" tile.
                        return MColors.elev2;
                    }

                    gradient: modelData.type === "primary" ? primaryGradient : null
                    Gradient {
                        id: primaryGradient
                        orientation: Gradient.Vertical
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealBright
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTealDark
                        }
                    }

                    border.width: 1
                    border.color: modelData.type === "primary" ? MColors.tealBorder : MColors.whiteOverlay08

                    // Top-only inset highlight — matches the JSX calculator
                    // "C" button reference (thin lighter stripe on the top
                    // edge, no border on the other 3 sides). Brighter on the
                    // primary =-pill (white-30) than on regular keys (w-06).
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        anchors.topMargin: 1
                        height: 1
                        color: key.modelData.type === "primary" ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.06)
                    }

                    // Outer halo only on the = pill.
                    Rectangle {
                        visible: key.modelData.type === "primary"
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: parent.radius + 3
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.22)
                        z: -1
                    }

                    Text {
                        anchors.centerIn: parent
                        text: key.modelData.k
                        color: {
                            if (key.modelData.type === "primary")
                                return MColors.textOnAccent;
                            if (key.modelData.type === "op")
                                return MColors.marathonTealBright;
                            return MColors.textPrimary;
                        }
                        font.family: MTypography.fontFamily
                        // Bold on "=" keeps its two strokes distinct from "−".
                        font.pixelSize: key.modelData.type === "primary" ? MTypography.sizeTitle1 : MTypography.sizeTitle3
                        font.weight: key.modelData.type === "primary" ? Font.Bold : Font.Light
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: ({
                            "C": "Clear",
                            "⌫": "Delete",
                            "%": "Percent",
                            "÷": "Divide",
                            "×": "Multiply",
                            "−": "Minus",
                            "+": "Plus",
                            "+/−": "Change sign",
                            ".": "Decimal point",
                            "=": "Equals"
                        })[modelData.k] || modelData.k
                    Accessible.onPressAction: keyArea.clicked(null)

                    scale: keyArea.pressed ? 0.96 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: MMotion.micro
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: MMotion.micro
                        }
                    }

                    MouseArea {
                        id: keyArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            calcApp.snapshot();
                            const k = key.modelData.k;
                            if (k === "C")
                                calcApp.clear();
                            else if (k === "=")
                                calcApp.calculate();
                            else if (k === "+/−")
                                calcApp.toggleSign();
                            else if (k === ".")
                                calcApp.appendDecimal();
                            else if ("+−×÷".indexOf(k) !== -1)
                                calcApp.setOperator(k);
                            else if ("0123456789".indexOf(k) !== -1)
                                calcApp.appendDigit(k);
                            else if (k === "%")
                                calcApp.applyScientific("percent");
                            else if (k === "⌫")
                                calcApp.backspace();
                        }
                    }
                }
            }
        }
    }
}
