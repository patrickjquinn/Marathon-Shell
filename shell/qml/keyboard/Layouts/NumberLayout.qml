import "../UI"
import MarathonOS.Shell
// Marathon Virtual Keyboard - Number Layout
// Full numeric keyboard with symbols
import QtQuick

Item {
    id: layout

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked

    implicitHeight: layoutColumn.implicitHeight

    Column {
        id: layoutColumn

        width: parent.width
        spacing: 0

        // Row 1: 1 2 3 4 5 6 7 8 9 0
        Row {
            readonly property real keyWidth: (width - spacing * 9) / 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

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

        // Row 2: @ # $ % & * ( ) -
        Row {
            readonly property real keyWidth: (width - spacing * 9) / 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["@", "#", "$", "%", "&", "*", "(", ")", "-", "+"]

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

        // Row 3: = / : ; , . ? ! Backspace
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["=", "/", ":", ";", ",", ".", "?", "!"]

                Key {
                    width: Math.round(50 * Constants.scaleFactor)
                    text: modelData
                    displayText: modelData
                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            // Backspace
            Key {
                width: Math.round(80 * Constants.scaleFactor)
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

        // Row 4: ABC Space Return
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

            // Space bar
            Key {
                width: Math.round(280 * Constants.scaleFactor)
                text: " "
                displayText: "space"
                onClicked: {
                    layout.spaceClicked();
                }
            }

            // Return key
            Key {
                width: Math.round(80 * Constants.scaleFactor)
                iconName: "corner-down-left"
                isSpecial: true
                onClicked: {
                    layout.enterClicked();
                }
            }
        }
    }
}
