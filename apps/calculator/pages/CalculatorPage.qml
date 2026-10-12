pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Ngf 1.0
import ".."

Page {
    id: page

    property Calculator calc
    property bool scientific: true

    function tap(k) {
        feedback.play();
        page.calc.press(k);
    }

    function keyFor(event) {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            return String(event.key - Qt.Key_0);
        switch (event.key) {
        case Qt.Key_Period:
        case Qt.Key_Comma:
            return ".";
        case Qt.Key_Plus:
            return "+";
        case Qt.Key_Minus:
            return "−";
        case Qt.Key_Asterisk:
        case Qt.Key_multiply:
            return "×";
        case Qt.Key_Slash:
        case Qt.Key_division:
            return "÷";
        case Qt.Key_Percent:
            return "%";
        case Qt.Key_Equal:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            return "=";
        case Qt.Key_Backspace:
            return "⌫";
        case Qt.Key_Escape:
        case Qt.Key_Delete:
            return "C";
        }
        return "";
    }

    // Forwarded first, so Escape clears before Page's own Escape goes back.
    Keys.forwardTo: [typing]

    Item {
        id: typing

        Keys.onPressed: function (event) {
            const k = page.keyFor(event);
            if (k === "" || (k === "C" && page.calc.isClear))
                return;
            event.accepted = true;
            page.tap(k);
        }
    }

    NonGraphicalFeedback {
        id: feedback
        event: "feedback_press"
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: height

        PullDownMenu {
            MenuItem {
                objectName: "modeItem"
                text: page.scientific ? qsTr("Basic mode") : qsTr("Scientific mode")
                onClicked: page.scientific = !page.scientific
            }
            MenuItem {
                objectName: "undoItem"
                text: qsTr("Undo")
                enabled: page.calc.canUndo
                onClicked: page.calc.undo()
            }
        }

        SilicaListView {
            id: history

            objectName: "history"
            anchors {
                top: parent.top
                bottom: display.top
                left: parent.left
                right: parent.right
                topMargin: Theme.paddingLarge
            }
            clip: true
            interactive: contentHeight > height
            verticalLayoutDirection: ListView.BottomToTop
            spacing: Theme.paddingMedium
            model: page.calc.history

            delegate: Column {
                id: entry

                required property var modelData

                width: history.width

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignRight
                    truncationMode: TruncationMode.Fade
                    text: entry.modelData.expression
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignRight
                    truncationMode: TruncationMode.Fade
                    text: entry.modelData.result
                    color: Theme.secondaryHighlightColor
                }
            }

            VerticalScrollDecorator {}
        }

        InfoLabel {
            objectName: "historyPlaceholder"
            anchors.centerIn: history
            visible: page.calc.history.length === 0
            text: qsTr("Calculations appear here")
        }

        Column {
            id: display

            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            anchors {
                bottom: functionKeys.visible ? functionKeys.top : keypad.top
                bottomMargin: Theme.paddingLarge
            }

            Label {
                objectName: "expression"
                width: parent.width
                horizontalAlignment: Text.AlignRight
                truncationMode: TruncationMode.Fade
                visible: text !== ""
                text: page.calc.lastExpression
                color: Theme.secondaryColor
            }
            Label {
                objectName: "result"
                width: parent.width
                horizontalAlignment: Text.AlignRight
                truncationMode: TruncationMode.Fade
                visible: text !== ""
                text: page.calc.lastResult
                color: Theme.highlightColor
            }
            Label {
                objectName: "display"
                width: parent.width
                height: Theme.itemSizeLarge
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.fontSizeLarge
                text: page.calc.displayText
                font.pixelSize: page.calc.errorText !== "" ? Theme.fontSizeExtraLarge : Theme.fontSizeHuge
                font.family: Theme.fontFamilyHeading
                color: page.calc.errorText !== "" ? Theme.errorColor : Theme.primaryColor
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }

        Grid {
            id: functionKeys

            objectName: "functionKeys"
            visible: page.scientific
            anchors {
                bottom: keypad.top
                left: parent.left
                right: parent.right
                leftMargin: Theme.paddingMedium
                rightMargin: Theme.paddingMedium
            }
            columns: 6

            Repeater {
                model: ["sin", "cos", "tan", "log", "ln", "!", "π", "√", "x²", "mod", "ans"]

                CalcKey {
                    required property string modelData

                    width: functionKeys.width / functionKeys.columns
                    height: Theme.itemSizeSmall
                    key: modelData
                    kind: "function"
                    onClicked: page.tap(key)
                }
            }
        }

        Grid {
            id: keypad

            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Theme.paddingMedium
            }
            columns: 4

            Repeater {
                model: [
                    { key: "C", kind: "soft" }, { key: "⌫", kind: "soft" }, { key: "%", kind: "soft" }, { key: "÷", kind: "op" },
                    { key: "7", kind: "digit" }, { key: "8", kind: "digit" }, { key: "9", kind: "digit" }, { key: "×", kind: "op" },
                    { key: "4", kind: "digit" }, { key: "5", kind: "digit" }, { key: "6", kind: "digit" }, { key: "−", kind: "op" },
                    { key: "1", kind: "digit" }, { key: "2", kind: "digit" }, { key: "3", kind: "digit" }, { key: "+", kind: "op" },
                    { key: "+/−", kind: "soft" }, { key: "0", kind: "digit" }, { key: ".", kind: "digit" }, { key: "=", kind: "equals" }
                ]

                CalcKey {
                    required property var modelData

                    width: keypad.width / keypad.columns
                    height: Theme.itemSizeLarge
                    key: modelData.key
                    kind: modelData.kind
                    onClicked: page.tap(key)
                }
            }
        }
    }
}
