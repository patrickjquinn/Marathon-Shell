pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

// Which finger, and the quick PIN that lets a finger be added.
Dialog {
    id: dialog

    readonly property var choices: {
        const left = Logic.fingersLeft(Security.enrolledFingers);
        return left.indexOf(finger) < 0 && finger !== "" ? [finger].concat(left) : left;
    }
    property string finger: Logic.fingersLeft(Security.enrolledFingers)[0] || ""
    property alias pin: pinField.text
    // Why the last try failed.
    property string error: ""

    canAccept: finger !== "" && pin.length >= 4
    acceptDestination: Qt.resolvedUrl("FingerprintEnrollPage.qml")
    acceptDestinationAction: PageStackAction.Replace
    // The page is made before the PIN is typed.
    onAccepted: {
        acceptDestinationInstance.finger = finger;
        acceptDestinationInstance.pin = pin;
    }

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Next")
            title: qsTr("Add fingerprint")
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            bottomPadding: Theme.paddingLarge
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            text: qsTr("Your quick PIN still unlocks the phone, and is asked for after a restart and after 5 fingers it doesn't recognize.")
        }
        ComboBox {
            id: fingerCombo

            objectName: "fingerCombo"
            width: parent.width
            label: qsTr("Finger")
            Binding on currentIndex {
                value: dialog.choices.indexOf(dialog.finger)
            }
            menu: ContextMenu {
                Repeater {
                    model: dialog.choices

                    MenuItem {
                        required property string modelData

                        text: Logic.fingerName(modelData)
                        onClicked: dialog.finger = modelData
                    }
                }
            }
        }
        PasswordField {
            id: pinField

            objectName: "pinField"
            width: parent.width
            label: qsTr("Quick PIN")
            placeholderText: label
            description: dialog.error
            errorHighlight: dialog.error !== ""
            inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData
            focus: true
            onTextChanged: dialog.error = ""
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
