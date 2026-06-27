import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Calculator (screens-apps-2.jsx:CalculatorApp).
//
// Top bar: Undo · Basic ▼ · menu · close.
// Display: right-aligned column — prior expression (small / tertiary),
// "= preview" (teal-bright), final Display-weight result.
// Scrollable function chip row (C · () · mod · π · √ · x² · sin …).
// 4 × 5 keypad — rounded-square elev-2 buttons with w-04 border:
//   row 1 ⬢ C  · ()  · %  · ÷       (ops in teal-bright)
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
    // Recent expressions, oldest first. Capped at 8 to bound memory and to
    // keep the on-screen history list short enough to read at a glance.
    property var history: []

    function fmt(n) {
        // Thousands separator. Strip trailing zeros after a decimal so
        // "0" doesn't render as "0.000000" under the default locale.
        if (n === undefined || isNaN(n))
            return "0";
        const fixed = Number(n).toFixed(8);
        const trimmed = fixed.indexOf(".") >= 0 ? fixed.replace(/\.?0+$/, "") : fixed;
        const parts = trimmed.split(".");
        const intPart = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return parts.length > 1 ? intPart + "." + parts[1] : intPart;
    }

    function appendDigit(digit) {
        if (newNumber) {
            display = digit;
            newNumber = false;
        } else {
            display = display === "0" ? digit : display + digit;
        }
    }

    function appendDecimal() {
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
        currentValue = parseFloat(display);
        currentOperator = op;
        newNumber = true;
    }

    function calculate() {
        const value = parseFloat(display);
        let result = currentValue;
        switch (currentOperator) {
        case "+":
            result = currentValue + value;
            break;
        case "-":
        case "−":
            result = currentValue - value;
            break;
        case "×":
            result = currentValue * value;
            break;
        case "÷":
            result = value !== 0 ? currentValue / value : 0;
            break;
        }
        lastExpression = fmt(currentValue) + " " + currentOperator + " " + fmt(value);
        lastResult = "= " + fmt(result);
        // Push to history. Reassigning the array (not .push) is what makes
        // QML's binding system notice — in-place mutation doesn't trigger
        // historyChanged.
        const next = history.slice();
        next.push({
            "expression": lastExpression,
            "result": lastResult
        });
        if (next.length > 8)
            next.shift();
        history = next;
        display = String(result);
        currentOperator = "";
        newNumber = true;
    }

    function clear() {
        display = "0";
        lastExpression = "";
        lastResult = "";
        history = [];
        currentValue = 0;
        currentOperator = "";
        newNumber = true;
    }

    appId: "calculator"
    appName: "Calculator"
    appIcon: "assets/icon.svg"

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        // ── Top bar — Undo · Basic ▼ · menu · close ─────────
        Item {
            id: topBar
            width: parent.width
            height: 60
            anchors.top: parent.top

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
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
                MouseArea {
                    anchors.fill: parent
                    onClicked: HapticService.light()
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Basic"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    font.weight: Font.Medium
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-down"
                    size: 16
                    color: MColors.textSecondary
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "menu"
                    size: 20
                    color: MColors.textSecondary
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "x"
                    size: 20
                    color: MColors.textSecondary
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
                width: ListView.view.width
                spacing: 1
                Text {
                    anchors.right: parent.right
                    text: modelData.expression
                    color: MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.features: ({
                            "tnum": 1
                        })
                }
                Text {
                    anchors.right: parent.right
                    text: modelData.result
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
            anchors.bottom: fnRow.top
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
                text: calcApp.fmt(parseFloat(calcApp.display))
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: 64
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
            height: 36
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            // C and ( ) are dropped here — they're already in the main
            // keypad below. Scientific row keeps only operators the basic
            // pad doesn't carry, to avoid the visual stutter of the same
            // glyph appearing twice 30 px apart.
            model: ["mod", "π", "√", "x²", "sin", "cos", "tan", "log", "ln", "!", "ans"]
            delegate: Rectangle {
                width: 56
                height: 36
                radius: MRadius.md
                color: chipArea.pressed ? MColors.bb10Card : "transparent"
                border.width: 1
                border.color: MColors.whiteOverlay08
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.weight: Font.Medium
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    onClicked: HapticService.light()
                    // Scientific chips are visual placeholders until
                    // the parser supports them — tapping just gives
                    // a haptic ack so users know the key registered.
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 80
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
                        k: "( )",
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
                        color: modelData.type === "primary" ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.06)
                    }

                    // Outer halo only on the = pill.
                    Rectangle {
                        visible: modelData.type === "primary"
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
                        text: modelData.k
                        color: {
                            if (modelData.type === "primary")
                                return "#000000";
                            if (modelData.type === "op")
                                return MColors.marathonTealBright;
                            return MColors.textPrimary;
                        }
                        font.family: MTypography.fontFamily
                        font.pixelSize: modelData.type === "primary" ? 28 : 24
                        font.weight: modelData.type === "primary" ? Font.DemiBold : Font.Light
                    }

                    scale: keyArea.pressed ? 0.96 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 80
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 80
                        }
                    }

                    MouseArea {
                        id: keyArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            const k = modelData.k;
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
                            // %, () are no-ops for now (basic mode).
                        }
                    }
                }
            }
        }
    }
}
