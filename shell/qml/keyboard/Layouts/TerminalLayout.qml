pragma ComponentBehavior: Bound

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
    signal cursorKeyClicked(int key)

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
                model: layout.row1Keys

                Key {
                    required property var modelData

                    width: row1.keyWidth
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
            id: row2
            readonly property real keyWidth: (width - spacing * 8) / 9

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Repeater {
                model: layout.row2Keys

                Key {
                    required property var modelData

                    width: row2.keyWidth
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
                text: "shift"  // i18n: not user-facing
                iconName: layout.capsLock ? "caret-double-up" : "chevron-up"
                isSpecial: true
                highlighted: layout.shifted || layout.capsLock
                onClicked: {
                    layout.shiftClicked();
                }
            }

            Repeater {
                model: layout.row3Keys

                Key {
                    required property var modelData

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
                text: "backspace"  // i18n: not user-facing
                iconName: "delete"
                autoRepeat: true
                isSpecial: true
                onClicked: {
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
            id: cursorRow

            property real availableWidth: width - spacing * 7

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)

            Key {
                width: cursorRow.availableWidth * 0.1
                text: "Esc"  // i18n: not user-facing
                //: terminal key name; usually kept as-is
                displayText: qsTr("Esc")
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Escape);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.1
                text: "Tab"  // i18n: not user-facing
                //: terminal key name; usually kept as-is
                displayText: qsTr("Tab")
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Tab);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.1
                text: "←"
                displayText: "←"
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Left);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.1
                text: "→"
                displayText: "→"
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Right);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.1
                text: "↑"
                displayText: "↑"
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Up);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.1
                text: "↓"
                displayText: "↓"
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Down);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.2
                text: "Ctrl"  // i18n: not user-facing
                //: terminal key name; usually kept as-is
                displayText: qsTr("Ctrl")
                isSpecial: true
                onClicked: {
                    layout.cursorKeyClicked(Qt.Key_Control);
                }
            }

            Key {
                width: cursorRow.availableWidth * 0.2
                text: "ABC"  // i18n: not user-facing
                //: Keyboard key that returns to the letter layout; use your script's first letters
                displayText: qsTr("ABC")
                isSpecial: true
                onClicked: {
                    layout.layoutSwitchClicked("qwerty");
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
                text: "-"
                displayText: "-"
                onClicked: {
                    layout.keyClicked("-");
                }
            }

            Key {
                width: row4.availableWidth * 0.5
                text: " "
                //: space bar key label
                displayText: qsTr("space")
                isSpecial: true
                onClicked: {
                    layout.spaceClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "dismiss"  // i18n: not user-facing
                iconName: "chevron-down"
                isSpecial: true
                onClicked: {
                    layout.dismissClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "/"
                displayText: "/"
                onClicked: {
                    layout.keyClicked("/");
                }
            }

            Key {
                width: row4.availableWidth * 0.14
                text: "enter"  // i18n: not user-facing
                iconName: "corner-down-left"
                isSpecial: true
                onClicked: {
                    layout.enterClicked();
                }
            }
        }
    }
}
