pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    // "set" or "remove" while the security service checks the system password.
    property string pending: ""
    property string pendingPin: ""

    function setPin(pin, password) {
        pending = "set";
        pendingPin = pin;
        Security.setQuickPIN(pin, password);
    }

    function removePin(password) {
        pending = "remove";
        Security.removeQuickPIN(password);
    }

    // After a wrong password the dialog comes back with the new PIN still filled in.
    function openPinDialog(pin, error) {
        const dialog = pageStack.push(Qt.resolvedUrl("QuickPinDialog.qml"), {
            changing: Security.hasQuickPIN,
            startupPin: Security.dataEncryption === "open" || Security.dataEncryption === "pin",
            pin: pin || "",
            confirmation: pin || "",
            error: error || ""
        });
        dialog.accepted.connect(() => page.setPin(dialog.pin, dialog.password));
    }

    function openRemoveDialog() {
        const dialog = pageStack.push(Qt.resolvedUrl("RemovePinDialog.qml"), {
            dataLocked: Security.dataEncryption === "pin"
        });
        dialog.accepted.connect(() => page.removePin(dialog.password));
    }

    Connections {
        target: Security

        function onQuickPINChanged() {
            if (page.pending !== "")
                Notices.show(page.pending === "set" ? qsTr("Quick PIN saved") : qsTr("Quick PIN removed"));
            page.pending = "";
        }
        function onAuthenticationFailed(reason) {
            const was = page.pending;
            page.pending = "";
            if (was === "set")
                page.openPinDialog(page.pendingPin, reason);
            else if (was === "remove")
                Notices.show(reason);
        }
    }

    component ActionItem: ListItem {
        id: action

        property alias text: label.text

        Label {
            id: label

            anchors {
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            color: action.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Security")
            }
            SectionHeader {
                text: qsTr("Device lock")
            }
            ComboBox {
                id: lockDelay

                readonly property var options: Logic.lockDelayOptions()

                objectName: "lockDelayCombo"
                width: parent.width
                label: qsTr("Lock after screen off")
                description: qsTr("Until then, a swipe unlocks without the PIN or password")
                Binding on currentIndex {
                    value: lockDelay.options.findIndex(option => option.seconds === Settings.autoLockTimeout)
                }
                menu: ContextMenu {
                    Repeater {
                        model: lockDelay.options

                        MenuItem {
                            required property var modelData

                            text: modelData.label
                            onClicked: Settings.autoLockTimeout = modelData.seconds
                        }
                    }
                }
            }
            ActionItem {
                objectName: "pinItem"
                text: Security.hasQuickPIN ? qsTr("Change quick PIN") : qsTr("Set quick PIN")
                enabled: page.pending === ""
                onClicked: page.openPinDialog("", "")
            }
            ActionItem {
                objectName: "removePinItem"
                visible: Security.hasQuickPIN
                text: qsTr("Remove quick PIN")
                enabled: page.pending === ""
                onClicked: page.openRemoveDialog()
            }
            Row {
                x: Theme.horizontalPageMargin
                height: Theme.itemSizeSmall
                spacing: Theme.paddingMedium
                visible: page.pending !== ""

                BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: BusyIndicatorSize.ExtraSmall
                    running: parent.visible
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Checking your password…")
                    color: Theme.highlightColor
                }
            }

            SectionHeader {
                objectName: "statusHeader"
                text: qsTr("Status")
                visible: fingerprint.visible || failedAttempts.visible || accountStatus.visible
            }
            DetailItem {
                id: fingerprint

                objectName: "fingerprint"
                visible: Security.fingerprintAvailable
                label: qsTr("Fingerprint")
                value: qsTr("Enrolled")
            }
            DetailItem {
                id: failedAttempts

                objectName: "failedAttempts"
                visible: Security.failedAttempts > 0
                label: qsTr("Failed attempts")
                value: String(Security.failedAttempts)
            }
            DetailItem {
                id: accountStatus

                objectName: "accountStatus"
                visible: Security.isLockedOut
                label: qsTr("Account")
                value: SettingsController.lockoutStatusText(Security.isLockedOut, Security.lockoutSecondsRemaining)
            }

            SectionHeader {
                text: qsTr("Data encryption")
            }
            DetailItem {
                objectName: "dataEncryption"
                label: qsTr("Your data")
                value: Logic.dataEncryptionValue(Security.dataEncryption)
            }
            Label {
                objectName: "dataEncryptionNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: Logic.dataEncryptionNote(Security.dataEncryption)
            }

            SectionHeader {
                text: qsTr("How it works")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Your device password always unlocks the lock screen. The quick PIN is an optional shortcut, stored encrypted. Wrong attempts are logged, and after 5 you have to wait before trying again, longer each time.")
            }
        }

        VerticalScrollDecorator {}
    }
}
