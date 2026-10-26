import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Layouts
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// Digits are cleared whenever the beat is hidden or shown: reset() runs from onVisibleChanged.
Item {
    id: root

    readonly property int requiredLength: 6
    // "enter" → first attempt, "confirm" → re-enter to verify.
    property string stage: "enter"
    property string enteredPin: ""
    property string confirmedPin: ""
    property string error: ""
    readonly property string currentPin: stage === "enter" ? enteredPin : confirmedPin

    signal done

    function reset() {
        stage = "enter";
        enteredPin = "";
        confirmedPin = "";
        error = "";
    }

    // Confirm steps back to enter; anything else lets the coordinator leave.
    function handleBack(): bool {
        const onConfirm = stage === "confirm";
        reset();
        return onConfirm;
    }

    function appendDigit(d) {
        if (currentPin.length >= requiredLength)
            return;
        if (stage === "enter")
            enteredPin += d;
        else
            confirmedPin += d;
        error = "";
        HapticManager.light();
        if (currentPin.length === requiredLength)
            tryAdvance();
    }

    function deleteDigit() {
        if (stage === "enter" && enteredPin.length > 0)
            enteredPin = enteredPin.slice(0, -1);
        else if (stage === "confirm" && confirmedPin.length > 0)
            confirmedPin = confirmedPin.slice(0, -1);
        HapticManager.light();
    }

    function tryAdvance() {
        if (stage === "enter") {
            stage = "confirm";
            error = "";
        } else if (confirmedPin !== enteredPin) {
            error = qsTr("Passcodes don't match. Try again.");
            confirmedPin = "";
            HapticManager.medium();
        } else {
            Security.setQuickPINFirstRun(enteredPin);
            error = "";
            HapticManager.medium();
            done();
        }
    }

    onVisibleChanged: {
        reset();
        if (visible)
            forceActiveFocus();
    }

    Keys.onPressed: function (event) {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            appendDigit(String.fromCharCode(event.key));
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            deleteDigit();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (currentPin.length >= requiredLength)
                tryAdvance();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Silica.Theme.paddingLarge
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingMedium

        Silica.Label {
            Layout.fillWidth: true
            //: Heading of the setup step that sets the passcode
            text: qsTr("Keep it private")
            wrapMode: Text.Wrap
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
        }

        Silica.Label {
            Layout.fillWidth: true
            text: root.stage === "enter" ? qsTr("Choose a passcode for your messages, photos and accounts.") : qsTr("Re-enter the same passcode.")
            wrapMode: Text.Wrap
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Silica.Theme.paddingLarge

            Repeater {
                model: root.requiredLength

                Rectangle {
                    required property int index

                    readonly property bool filled: index < root.currentPin.length

                    objectName: "oobeDot" + index
                    Layout.preferredWidth: Silica.Theme.paddingLarge
                    Layout.preferredHeight: Silica.Theme.paddingLarge
                    radius: width / 2
                    color: filled ? Silica.Theme.highlightColor : "transparent"
                    border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                    border.color: filled ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }
                }
            }
        }

        Silica.Label {
            objectName: "oobeError"
            Layout.fillWidth: true
            text: root.error
            opacity: root.error.length > 0 ? 1 : 0
            color: Silica.Theme.errorColor
            font.pixelSize: Silica.Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        Item {
            id: padArea

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: -Silica.Theme.horizontalPageMargin
            Layout.rightMargin: -Silica.Theme.horizontalPageMargin

            // Shrinks to fit short screens rather than clipping the bottom row.
            Item {
                id: pad

                readonly property real step: keypad._buttonWidth + keypad._horizontalSpacing

                width: padArea.width
                height: keypad.height
                anchors.horizontalCenter: parent.horizontalCenter
                scale: Math.min(1, padArea.height / height)
                transformOrigin: Item.Top

                Silica.Keypad {
                    id: keypad

                    objectName: "oobeKeypad"
                    width: parent.width
                    vanityDialNumbersVisible: false
                    symbolsVisible: false
                    onClicked: function (number) {
                        root.appendDigit(number);
                    }
                }

                Silica.IconButton {
                    objectName: "oobeDelete"
                    // Right-hand column of the bottom row, beside 0.
                    x: (pad.width - 3 * keypad._buttonWidth - 2 * keypad._horizontalSpacing) / 2 + 2 * pad.step + (keypad._buttonWidth - width) / 2
                    y: pad.height - keypad._buttonHeight + (keypad._buttonHeight - height) / 2
                    enabled: root.currentPin.length > 0
                    icon.source: "image://theme/icon-m-backspace"
                    Accessible.name: qsTr("Delete")
                    onClicked: root.deleteDigit()
                }
            }
        }
    }
}
