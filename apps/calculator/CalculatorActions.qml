import QtQuick
import Keel.Actions 1.0

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml CalculatorActions.qml --app-id org.marathonos.calculator \
//       --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app's calculator, for its history.
    property Calculator calc
    property Calculator scratch: Calculator {}

    // "12.5 + sqrt" -> ["1", "2", ".", "5", "+", "√"]; null if a token is not a key.
    function keysOf(expression) {
        const aliases = { "-": "−", "*": "×", "/": "÷", "sqrt": "√", "pi": "π", "²": "x²" };
        const allowed = scratch.keys.filter(k => ["C", "⌫", "ans"].indexOf(k) === -1);
        const token = /(\d+(?:\.\d*)?|\.\d+|mod|sin|cos|tan|log|ln|sqrt|pi|x²|\S)\s*/y;
        const text = expression.trim();
        const keys = [];
        while (token.lastIndex < text.length) {
            const t = token.exec(text)[1];
            const key = aliases[t] || t;
            if (/^[\d.]/.test(key))
                keys.push(...key.split(""));
            else if (allowed.indexOf(key) !== -1)
                keys.push(key);
            else
                return null;
        }
        return keys;
    }

    KeelAction {
        name: "calc.evaluate"
        title: qsTr("Calculate")
        description: "Work out a calculation on Marathon Calculator's keypad and return the result. The expression is what would be typed: numbers, + - * / mod %, and √ (or sqrt), x², sin, cos, tan (in degrees), log, ln and ! after the number they apply to; π (or pi) and e are constants. Like the keypad, operators apply in the order typed, without precedence: 2 + 3 * 4 is 20."
        readOnly: true
        idempotent: true
        parameters: [
            KeelParam { name: "expression"; type: "string"; required: true; minLength: 1; maxLength: 200; description: "For example 12.5 * 4 - 3" }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "value"; type: "number"; required: true }
            KeelParam { name: "text"; type: "string"; maxLength: 64; required: true; description: "The result as the app shows it" }
        }
        onInvoked: (args, call) => {
            const keys = root.keysOf(args.expression);
            if (keys === null) {
                call.fail("InvalidArguments", "The expression has something the keypad does not have");
                return;
            }
            root.scratch.clear();
            keys.forEach(k => root.scratch.press(k));
            root.scratch.press("=");
            if (root.scratch.errorText !== "")
                call.fail("Failed", root.scratch.errorText);
            else
                call.reply({ value: parseFloat(root.scratch.display), text: root.scratch.displayText });
        }
    }

    KeelAction {
        name: "calc.history"
        title: qsTr("Calculation history")
        description: "The calculations on Marathon Calculator's tape, oldest first (at most 8), each with its expression as the app shows it and its result."
        readOnly: true
        idempotent: true
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 8
            KeelParam { name: "expression"; type: "string"; maxLength: 200; required: true }
            KeelParam { name: "value"; type: "number"; required: true }
        }
        onInvoked: (args, call) => call.reply(root.calc.history.map(h => ({ expression: String(h.expression), value: Number(h.value) })))
    }
}
