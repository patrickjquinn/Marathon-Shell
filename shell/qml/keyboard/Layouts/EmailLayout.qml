import "../UI"
import QtQuick

Item {
    id: layout

    property bool shifted: false

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

        Row {
            id: row1
            readonly property real keyWidth: (width - spacing * 9) / 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]

                Key {
                    width: row1.keyWidth
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

        Row {
            id: row2
            readonly property real keyWidth: (width - spacing * 9) / 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "@"]

                Key {
                    width: row2.keyWidth
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

        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: Math.round(60 * Constants.scaleFactor)
                iconName: layout.shifted ? "chevrons-up" : "chevron-up"
                isSpecial: true
                highlighted: layout.shifted
                onClicked: {
                    layout.shifted = !layout.shifted;
                }
            }

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

        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: Math.round(55 * Constants.scaleFactor)
                text: "123"
                displayText: "123"
                isSpecial: true
                onClicked: {
                    layout.layoutSwitchClicked("symbols");
                }
            }

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

            Key {
                width: Math.round(120 * Constants.scaleFactor)
                text: " "
                displayText: "space"
                onClicked: {
                    layout.spaceClicked();
                }
            }

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
