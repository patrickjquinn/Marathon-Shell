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
                    required property string modelData

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
                    required property string modelData

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
            id: row3
            readonly property real unitWidth: (width - spacing * 8) / 11.4
            readonly property real sideKeyWidth: unitWidth * 1.7

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: row3.sideKeyWidth
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
                    required property string modelData

                    width: row3.unitWidth
                    text: modelData
                    displayText: layout.shifted ? modelData.toUpperCase() : modelData
                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                }
            }

            Key {
                width: row3.sideKeyWidth
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
            id: row4
            readonly property real availableWidth: width - spacing * 7

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: row4.availableWidth * 0.12
                text: "123"
                displayText: "123"
                isSpecial: true
                onClicked: {
                    layout.layoutSwitchClicked("symbols");
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "."
                displayText: "."
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "_"
                displayText: "_"
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "-"
                displayText: "-"
            }

            Key {
                width: row4.availableWidth * 0.30
                text: " "
                displayText: "space"
                onClicked: {
                    layout.spaceClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.12
                text: ".com"
                displayText: ".com"
                isSpecial: true
                onClicked: {
                    layout.keyClicked(".com");
                }
            }

            Key {
                width: row4.availableWidth * 0.10
                text: ".net"
                displayText: ".net"
                isSpecial: true
                onClicked: {
                    layout.keyClicked(".net");
                }
            }

            Key {
                width: row4.availableWidth * 0.12
                iconName: "corner-down-left"
                isSpecial: true
                onClicked: {
                    layout.enterClicked();
                }
            }
        }
    }
}
