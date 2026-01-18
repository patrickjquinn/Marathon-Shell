import "../UI"
import MarathonUI.Theme
import QtQuick

Item {
    id: layout

    property bool shifted: false
    readonly property var row1Keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    readonly property var row2Keys: ["@", "#", "$", "_", "&", "-", "+", "(", ")", "/"]
    readonly property var row3Keys: ["*", "\"", "'", ":", ";", "!", "?", "~", "`"]

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
                model: row1Keys

                Key {
                    width: row1.keyWidth
                    text: modelData
                    displayText: modelData
                    onClicked: layout.keyClicked(displayText)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"
        }

        Row {
            id: row2
            readonly property real keyWidth: (width - spacing * 9) / 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: row2Keys

                Key {
                    width: row2.keyWidth
                    text: modelData
                    displayText: modelData
                    onClicked: layout.keyClicked(displayText)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: MColors.border
            opacity: 0.3
        }

        Row {
            id: row3

            property real availableWidth: width - spacing * 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: row3.availableWidth * 0.15
                text: "=\\<"
                displayText: "=\\<"
                isSpecial: true
                onClicked: Logger.info("SymbolLayout", "Shift symbols - not yet implemented")
            }

            Repeater {
                model: row3Keys

                Key {
                    width: row3.availableWidth * 0.075
                    text: modelData
                    displayText: modelData
                    onClicked: layout.keyClicked(displayText)
                }
            }

            Key {
                width: row3.availableWidth * 0.175
                text: "backspace"
                iconName: "delete"
                isSpecial: true
                onClicked: layout.backspaceClicked()
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: MColors.border
            opacity: 0.3
        }

        Row {
            id: row4

            property real availableWidth: width - spacing * 5

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: row4.availableWidth * 0.12
                text: "ABC"
                displayText: "ABC"
                isSpecial: true
                onClicked: layout.layoutSwitchClicked("qwerty")
            }

            Key {
                width: row4.availableWidth * 0.08
                text: ","
                displayText: ","
                onClicked: layout.keyClicked(",")
            }

            Key {
                width: row4.availableWidth * 0.5
                text: " "
                displayText: "space"
                isSpecial: true
                onClicked: layout.spaceClicked()
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "dismiss"
                iconName: "chevron-down"
                isSpecial: true
                onClicked: layout.dismissClicked()
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "."
                displayText: "."
                onClicked: layout.keyClicked(".")
            }

            Key {
                width: row4.availableWidth * 0.14
                text: "enter"
                iconName: "corner-down-left"
                isSpecial: true
                onClicked: layout.enterClicked()
            }
        }
    }
}
