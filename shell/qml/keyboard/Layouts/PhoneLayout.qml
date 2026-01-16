import "../UI"
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

        Row {
            id: row1
            readonly property real keyWidth: (width - spacing * 6) / 7

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: ["1", "2", "3", "+", "-", "(", ")"]

                Key {
                    width: row1.keyWidth
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

        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

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
