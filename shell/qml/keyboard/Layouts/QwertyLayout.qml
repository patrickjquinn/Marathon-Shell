import "../Data"
import "../UI"
import MarathonOS.Shell
import QtQuick

Item {
    id: layout

    property bool shifted: false
    property bool capsLock: false
    readonly property var row1Keys: [
        {
            "char": "q",
            "alts": []
        },
        {
            "char": "w",
            "alts": []
        },
        {
            "char": "e",
            "alts": ["è", "é", "ê", "ë", "ē"]
        },
        {
            "char": "r",
            "alts": []
        },
        {
            "char": "t",
            "alts": ["þ"]
        },
        {
            "char": "y",
            "alts": ["ý", "ÿ"]
        },
        {
            "char": "u",
            "alts": ["ù", "ú", "û", "ü", "ū"]
        },
        {
            "char": "i",
            "alts": ["ì", "í", "î", "ï", "ī"]
        },
        {
            "char": "o",
            "alts": ["ò", "ó", "ô", "õ", "ö", "ø", "ō"]
        },
        {
            "char": "p",
            "alts": []
        }
    ]
    readonly property var row2Keys: [
        {
            "char": "a",
            "alts": ["à", "á", "â", "ã", "ä", "å", "æ", "ā"]
        },
        {
            "char": "s",
            "alts": ["ś", "š", "ş", "ß"]
        },
        {
            "char": "d",
            "alts": ["ð"]
        },
        {
            "char": "f",
            "alts": []
        },
        {
            "char": "g",
            "alts": []
        },
        {
            "char": "h",
            "alts": []
        },
        {
            "char": "j",
            "alts": []
        },
        {
            "char": "k",
            "alts": []
        },
        {
            "char": "l",
            "alts": ["ł"]
        }
    ]
    readonly property var row3Keys: [
        {
            "char": "z",
            "alts": ["ź", "ż", "ž"]
        },
        {
            "char": "x",
            "alts": []
        },
        {
            "char": "c",
            "alts": ["ç", "ć", "č"]
        },
        {
            "char": "v",
            "alts": []
        },
        {
            "char": "b",
            "alts": []
        },
        {
            "char": "n",
            "alts": ["ñ", "ń"]
        },
        {
            "char": "m",
            "alts": []
        }
    ]

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal shiftClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked

    implicitHeight: layoutColumn.implicitHeight

    Column {
        id: layoutColumn

        width: parent.width
        spacing: 0

        Row {
            readonly property real keyWidth: (width - spacing * 9) / 10

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: row1Keys

                Key {
                    width: parent.keyWidth
                    text: modelData.char
                    displayText: layout.shifted || layout.capsLock ? modelData.char.toUpperCase() : modelData.char
                    alternateChars: modelData.alts
                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                    onAlternateSelected: function (character) {
                        layout.keyClicked(character);
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"
        }

        Row {
            readonly property real keyWidth: (width - spacing * 8) / 9

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: row2Keys

                Key {
                    width: parent.keyWidth
                    text: modelData.char
                    displayText: layout.shifted || layout.capsLock ? modelData.char.toUpperCase() : modelData.char
                    alternateChars: modelData.alts
                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                    onAlternateSelected: function (character) {
                        layout.keyClicked(character);
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"
        }

        Row {
            id: row3

            property real availableWidth: width - spacing * 8

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: row3.availableWidth * 0.15
                text: "shift"
                iconName: layout.capsLock ? "chevrons-up" : "chevron-up"
                isSpecial: true
                highlighted: layout.shifted || layout.capsLock
                onClicked: {
                    layout.shiftClicked();
                }
            }

            Repeater {
                model: row3Keys

                Key {
                    width: row3.availableWidth * 0.1
                    text: modelData.char
                    displayText: layout.shifted || layout.capsLock ? modelData.char.toUpperCase() : modelData.char
                    alternateChars: modelData.alts
                    onClicked: {
                        layout.keyClicked(displayText);
                    }
                    onAlternateSelected: function (character) {
                        layout.keyClicked(character);
                    }
                }
            }

            Key {
                id: backspaceKey

                width: row3.availableWidth * 0.15
                text: "backspace"
                iconName: "delete"
                isSpecial: true
                onClicked: {
                    if (!backspaceRepeatTimer.running)
                        layout.backspaceClicked();
                }
                onPressAndHold: {
                    backspaceRepeatTimer.start();
                }
                onReleased: {
                    backspaceRepeatTimer.stop();
                }
            }

            Timer {
                id: backspaceRepeatTimer

                interval: 50
                repeat: true
                onTriggered: {
                    layout.backspaceClicked();
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"
        }

        Row {
            id: row4

            property real availableWidth: width - spacing * 5

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
                text: "emoji"
                displayText: "😀"
                isSpecial: true
                fontFamily: "Noto Color Emoji"
                onClicked: {
                    layout.layoutSwitchClicked("emoji");
                }
            }

            Key {
                width: row4.availableWidth * 0.5
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
