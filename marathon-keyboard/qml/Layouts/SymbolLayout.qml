// Marathon Virtual Keyboard - Symbol Layout
// Special characters and symbols
import QtQuick
import "../UI"

Item {
    id: layout

    property bool shifted: false

    // Expose Column's implicit height
    implicitHeight: layoutColumn.implicitHeight

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked

    // Symbol key definitions
    readonly property var row1Keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    readonly property var row2Keys: ["@", "#", "$", "_", "&", "-", "+", "(", ")", "/"]
    readonly property var row3Keys: ["*", "\"", "'", ":", ";", "!", "?", "~", "`"]

    Column {
        id: layoutColumn
        width: parent.width
        spacing: 0

        // Row 1: 1 2 3 4 5 6 7 8 9 0
        Row {
            width: parent.width
            spacing: Math.round(1 * scaleFactor)
            readonly property real keyWidth: (width - spacing * 9) / 10

            Repeater {
                model: row1Keys

                Key {
                    width: parent.keyWidth
                    text: modelData
                    displayText: modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }
        }

        // Separator line between Row 1 and Row 2
        Rectangle {
            width: parent.width
            height: Math.round(2 * scaleFactor)
            color: "#666666"  // BRIGHT grey line - very visible
            opacity: 1.0
        }

        // Row 2: @ # $ _ & - + ( ) /
        Row {
            width: parent.width
            spacing: Math.round(1 * scaleFactor)
            readonly property real keyWidth: (width - spacing * 9) / 10

            Repeater {
                model: row2Keys

                Key {
                    width: parent.keyWidth
                    text: modelData
                    displayText: modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }
        }

        // Separator line between Row 2 and Row 3
        Rectangle {
            width: parent.width
            height: 1
            color: keyboard ? keyboard.borderColor : "#3E3E42"
            opacity: 0.3
        }

        // Row 3: =\< * " ' : ; ! ? ~ ` Backspace
        Row {
            id: row3
            width: parent.width
            spacing: Math.round(1 * scaleFactor)
            property real availableWidth: width - spacing * 10

            // Shift key (switches to alternate symbols)
            Key {
                width: row3.availableWidth * 0.15
                text: "=\\<"
                displayText: "=\\<"
                isSpecial: true

                onClicked: {
                    keyboard.logMessage("SymbolLayout", "Shift symbols - not yet implemented");
                }
            }

            // Symbol keys
            Repeater {
                model: row3Keys

                Key {
                    width: row3.availableWidth * 0.10
                    text: modelData
                    displayText: modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            // Backspace key
            Key {
                width: row3.availableWidth * 0.15
                text: "backspace"
                iconName: "delete"
                isSpecial: true

                onClicked: {
                    layout.backspaceClicked();
                }
            }
        }

        // Separator line between Row 3 and Row 4
        Rectangle {
            width: parent.width
            height: 1
            color: keyboard ? keyboard.borderColor : "#3E3E42"
            opacity: 0.3
        }

        // Row 4: ABC, Comma, Space, Dismiss, Period, Enter (matching QWERTY layout)
        Row {
            id: row4
            width: parent.width
            spacing: Math.round(1 * scaleFactor)
            property real availableWidth: width - spacing * 5

            // ABC key (back to letters)
            Key {
                width: row4.availableWidth * 0.12
                text: "ABC"
                displayText: "ABC"
                isSpecial: true

                onClicked: {
                    layout.layoutSwitchClicked("qwerty");
                }
            }

            // Comma key
            Key {
                width: row4.availableWidth * 0.08
                text: ","
                displayText: ","

                onClicked: {
                    layout.keyClicked(",");
                }
            }

            // Space bar (MASSIVE - 50% of row)
            Key {
                width: row4.availableWidth * 0.50
                text: " "
                displayText: "space"
                isSpecial: true

                onClicked: {
                    layout.spaceClicked();
                }
            }

            // Dismiss key (keyboard down icon) - LEFT OF ENTER
            Key {
                width: row4.availableWidth * 0.08
                text: "dismiss"
                iconName: "chevron-down"
                isSpecial: true

                onClicked: {
                    layout.dismissClicked();
                }
            }

            // Period key
            Key {
                width: row4.availableWidth * 0.08
                text: "."
                displayText: "."

                onClicked: {
                    layout.keyClicked(".");
                }
            }

            // Enter key (rightmost)
            Key {
                width: row4.availableWidth * 0.14
                text: "enter"
                iconName: "corner-down-left"
                isSpecial: true

                onClicked: {
                    layout.enterClicked();
                }
            }
        }
    }
}
