import QtQuick

Item {
    id: dynamicLayout

    property bool shifted: false
    property bool capsLock: false
    property var layoutData: null // Set via Connections.onLayoutLoaded only
    property bool rtl: dynamicLayout.layoutData ? dynamicLayout.layoutData.rtl : false
    property bool isLoading: dynamicLayout.layoutData === null

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal shiftClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked
    signal languageSwitchClicked

    implicitHeight: layoutColumn.implicitHeight
    // Initialize from LanguageManager if already loaded (for hot reloading)
    Component.onCompleted: {
        if (LanguageManager.currentLayout)
            dynamicLayout.layoutData = LanguageManager.currentLayout;
    }

    Column {
        id: layoutColumn

        width: parent.width
        spacing: 0

        Repeater {
            id: rowRepeater

            model: dynamicLayout.layoutData ? dynamicLayout.layoutData.rows : []

            delegate: Column {
                id: rowDelegate

                required property var modelData
                required property int index

                width: layoutColumn.width
                spacing: 0

                Row {
                    id: keyRow

                    property var rowData: rowDelegate.modelData
                    property bool isLastRow: index === (dynamicLayout.layoutData.rows.length - 1)
                    property int charKeyCount: keyRow.rowData.keys.length
                    property real sideKeyWidth: isLastRow ? Math.floor(keyRow.width * 0.15) : 0
                    property real totalSideWidth: sideKeyWidth * 2
                    property int gapCount: isLastRow ? (charKeyCount + 1) : (charKeyCount - 1)
                    property real totalSpacing: keyRow.spacing * gapCount
                    property real availableForChars: keyRow.width - (isLastRow ? totalSideWidth : 0) - totalSpacing
                    property real keyWidth: availableForChars / charKeyCount

                    width: parent.width
                    spacing: Math.round(1 * Constants.scaleFactor)
                    layoutDirection: dynamicLayout.rtl ? Qt.RightToLeft : Qt.LeftToRight

                    Key {
                        visible: keyRow.isLastRow
                        width: keyRow.sideKeyWidth
                        text: "shift"
                        iconName: dynamicLayout.capsLock ? "chevrons-up" : "chevron-up"
                        isSpecial: true
                        highlighted: dynamicLayout.shifted || dynamicLayout.capsLock
                        onClicked: {
                            dynamicLayout.shiftClicked();
                        }
                    }

                    Repeater {
                        model: keyRow.rowData.keys

                        delegate: Key {
                            id: keyDelegate

                            required property var modelData

                            width: keyRow.keyWidth
                            text: keyDelegate.modelData.char
                            displayText: dynamicLayout.shifted || dynamicLayout.capsLock ? keyDelegate.modelData.char.toUpperCase() : keyDelegate.modelData.char
                            alternateChars: keyDelegate.modelData.alts
                            onClicked: {
                                dynamicLayout.keyClicked(keyDelegate.displayText);
                            }
                            onAlternateSelected: function (character) {
                                dynamicLayout.keyClicked(character);
                            }
                        }
                    }

                    Key {
                        id: backspaceKey

                        visible: keyRow.isLastRow
                        width: keyRow.sideKeyWidth
                        text: "backspace"
                        iconName: "delete"
                        isSpecial: true
                        onClicked: {
                            if (!backspaceRepeatTimer.running)
                                dynamicLayout.backspaceClicked();
                        }
                        onPressAndHold: {
                            backspaceRepeatTimer.start();
                        }
                        onReleased: {
                            backspaceRepeatTimer.stop();
                        }

                        Timer {
                            id: backspaceRepeatTimer

                            interval: 50
                            repeat: true
                            onTriggered: {
                                dynamicLayout.backspaceClicked();
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 2
                    color: "#666666"
                    visible: rowDelegate.index < (dynamicLayout.layoutData.rows.length - 1)
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

            property real availableWidth: row4.width - row4.spacing * 5

            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            layoutDirection: dynamicLayout.rtl ? Qt.RightToLeft : Qt.LeftToRight

            Key {
                width: row4.availableWidth * 0.12
                text: "123"
                displayText: "123"
                isSpecial: true
                onClicked: {
                    dynamicLayout.layoutSwitchClicked("symbols");
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "emoji"
                displayText: "😀"
                isSpecial: true
                fontFamily: "Noto Color Emoji"
                onClicked: {
                    dynamicLayout.layoutSwitchClicked("emoji");
                }
                onPressAndHold: {
                    dynamicLayout.languageSwitchClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.5
                text: " "
                displayText: "space"
                isSpecial: true
                onClicked: {
                    dynamicLayout.spaceClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "dismiss"
                iconName: "chevron-down"
                isSpecial: true
                onClicked: {
                    dynamicLayout.dismissClicked();
                }
            }

            Key {
                width: row4.availableWidth * 0.08
                text: "."
                displayText: "."
                onClicked: {
                    dynamicLayout.keyClicked(".");
                }
            }

            Key {
                width: row4.availableWidth * 0.14
                text: "enter"
                iconName: "corner-down-left"
                isSpecial: true
                onClicked: {
                    dynamicLayout.enterClicked();
                }
            }
        }
    }

    Connections {
        function onLayoutLoaded(layout) {
            dynamicLayout.layoutData = layout;
        }

        target: LanguageManager
    }
}
