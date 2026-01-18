import QtQuick
import "../UI"

Item {
    id: layout

    property bool shifted: false

    implicitHeight: layoutColumn.implicitHeight

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked

    readonly property var row1Keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    readonly property var row2Keys: ["@", "#", "$", "_", "&", "-", "+", "(", ")", "/"]
    readonly property var row3Keys: ["*", "\"", "'", ":", ";", "!", "?", "~", "`"]

    Column {
        id: layoutColumn
        width: parent.width
        spacing: 0

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

        Rectangle {
            width: parent.width
            height: Math.round(2 * scaleFactor)
            color: "#666666"
            opacity: 1.0
        }

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

        Rectangle {
            width: parent.width
            height: 1
            color: keyboard ? keyboard.borderColor : "#3E3E42"
            opacity: 0.3
        }

        Row {
            id: row3
            width: parent.width
            spacing: Math.round(1 * scaleFactor)
            property real availableWidth: width - spacing * 10

            Key {
                width: row3.availableWidth * 0.15
                text: "=\\<"
                displayText: "=\\<"
                isSpecial: true

                onClicked: {
                    keyboard.logMessage("SymbolLayout", "Shift symbols - not yet implemented");
                }
            }

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

        Rectangle {
            width: parent.width
            height: 1
            color: keyboard ? keyboard.borderColor : "#3E3E42"
            opacity: 0.3
        }

        Row {
            id: row4
            width: parent.width
            spacing: Math.round(1 * scaleFactor)
            property real availableWidth: width - spacing * 5

            Key {
                width: row4.availableWidth * 0.12
                text: "ABC"
                displayText: "ABC"
                isSpecial: true

                onClicked: {
                    layout.layoutSwitchClicked("qwerty");
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: ","
                displayText: ","

                onClicked: {
                    layout.keyClicked(",");
                }
            }

            Key {
                width: row4.availableWidth * 0.50
                text: " "
                displayText: "space"
                isSpecial: true

                onClicked: {
                    layout.spaceClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "dismiss"
                iconName: "chevron-down"
                isSpecial: true

                onClicked: {
                    layout.dismissClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "."
                displayText: "."

                onClicked: {
                    layout.keyClicked(".");
                }
            }

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
