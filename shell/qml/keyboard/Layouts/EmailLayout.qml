// Marathon Virtual Keyboard - Email Layout
// Optimized for email addresses with @ and domain shortcuts
import QtQuick
import MarathonOS.Shell
import "../UI"

Item {
    id: layout

    // Properties
    property bool shifted: false

    // Expose Column's implicit height
    implicitHeight: layoutColumn.implicitHeight

    // Signals
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

        // Row 1: Q W E R T Y U I O P
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            readonly property real keyWidth: (width - spacing * 9) / 10

            Repeater {
                model: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]

                Key {
                    width: parent.keyWidth
                    text: modelData
                    displayText: layout.shifted ? modelData.toUpperCase() : modelData

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

        // Row 2: A S D F G H J K L @
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            readonly property real keyWidth: (width - spacing * 9) / 10

            Repeater {
                model: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "@"]

                Key {
                    width: parent.keyWidth
                    text: modelData
                    displayText: (modelData === "@" || !layout.shifted) ? modelData : modelData.toUpperCase()
                    isSpecial: modelData === "@"

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

        // Row 3: Shift Z X C V B N M Backspace
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            // Shift key
            Key {
                width: Math.round(60 * Constants.scaleFactor)
                iconName: layout.capsLock ? "chevrons-up" : "chevron-up"
                isSpecial: true
                highlighted: layout.shifted

                onClicked: {
                    layout.shifted = !layout.shifted;
                }
            }

            // Letter keys
            Repeater {
                model: ["z", "x", "c", "v", "b", "n", "m"]

                Key {
                    width: Math.round(55 * Constants.scaleFactor)
                    text: modelData
                    displayText: layout.shifted ? modelData.toUpperCase() : modelData

                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            // Backspace
            Key {
                width: Math.round(60 * Constants.scaleFactor)
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

        // Row 4: 123 . _ - Space .com .net Return
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            // 123 key
            Key {
                width: Math.round(55 * Constants.scaleFactor)
                text: "123"
                displayText: "123"
                isSpecial: true

                onClicked: {
                    layout.layoutSwitchClicked("symbols");
                }
            }

            // Common email characters
            Key {
                width: Math.round(40 * Constants.scaleFactor)
                text: "."
                displayText: "."
            }

            Key {
                width: Math.round(40 * Constants.scaleFactor)
                text: "_"
                displayText: "_"
            }

            Key {
                width: Math.round(40 * Constants.scaleFactor)
                text: "-"
                displayText: "-"
            }

            // Space bar
            Key {
                width: Math.round(120 * Constants.scaleFactor)
                text: " "
                displayText: "space"

                onClicked: {
                    layout.spaceClicked();
                }
            }

            // Domain shortcuts
            Key {
                width: Math.round(55 * Constants.scaleFactor)
                text: ".com"
                displayText: ".com"
                isSpecial: true

                onClicked: {
                    layout.keyClicked(".com");
                }
            }

            Key {
                width: Math.round(50 * Constants.scaleFactor)
                text: ".net"
                displayText: ".net"
                isSpecial: true

                onClicked: {
                    layout.keyClicked(".net");
                }
            }

            // Return key
            Key {
                width: Math.round(60 * Constants.scaleFactor)
                iconName: "corner-down-left"
                isSpecial: true

                onClicked: {
                    layout.enterClicked();
                }
            }
        }
    }
}
