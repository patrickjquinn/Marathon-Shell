// Marathon Virtual Keyboard - Phone Layout
// Phone number pad with common symbols
import QtQuick
import MarathonOS.Shell
import "../UI"

Item {
    id: layout

    implicitHeight: layoutColumn.implicitHeight

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked

    Column {
        id: layoutColumn
        width: parent.width
        spacing: 0

        // Row 1: 1 2 3 + - ( )
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            readonly property real keyWidth: (width - spacing * 6) / 7

            Repeater {
                model: ["1", "2", "3", "+", "-", "(", ")"]

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
            height: Math.round(1 * Constants.scaleFactor)
            color: "#666666"
        }

        // Row 2: 4 5 6 # * Backspace
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["4", "5", "6", "#", "*"]

                Key {
                    width: Math.round(65 * Constants.scaleFactor)
                    text: modelData
                    displayText: modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            // Backspace
            Key {
                width: Math.round(100 * Constants.scaleFactor)
                iconName: "delete"
                isSpecial: true

                onClicked: {
                    layout.backspaceClicked();
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(1 * Constants.scaleFactor)
            color: "#666666"
        }

        // Row 3: 7 8 9 , . Space
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["7", "8", "9", ",", "."]

                Key {
                    width: Math.round(65 * Constants.scaleFactor)
                    text: modelData
                    displayText: modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            // Space bar
            Key {
                width: Math.round(100 * Constants.scaleFactor)
                text: " "
                displayText: "space"

                onClicked: {
                    layout.spaceClicked();
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(1 * Constants.scaleFactor)
            color: "#666666"
        }

        // Row 4: ABC * 0 # Return
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            // ABC key
            Key {
                width: Math.round(80 * Constants.scaleFactor)
                text: "ABC"
                displayText: "ABC"
                isSpecial: true

                onClicked: {
                    layout.layoutSwitchClicked("qwerty");
                }
            }

            Repeater {
                model: ["*", "0", "#"]

                Key {
                    width: Math.round(80 * Constants.scaleFactor)
                    text: modelData
                    displayText: modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            // Return key
            Key {
                width: Math.round(120 * Constants.scaleFactor)
                iconName: "corner-down-left"
                isSpecial: true

                onClicked: {
                    layout.enterClicked();
                }
            }
        }
    }
}
