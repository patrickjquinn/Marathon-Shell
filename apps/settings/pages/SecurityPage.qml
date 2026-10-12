pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    // "set" or "remove" while the security service checks the system password.
    property string pending: ""

    function setPin(pin, password) {
        pending = "set";
        Security.setQuickPIN(pin, password);
    }

    function removePin(password) {
        pending = "remove";
        Security.removeQuickPIN(password);
    }

    function openPinDialog() {
        const dialog = pageStack.push(Qt.resolvedUrl("QuickPinDialog.qml"), { changing: Security.hasQuickPIN });
        dialog.accepted.connect(() => page.setPin(dialog.pin, dialog.password));
    }

    function openRemoveDialog() {
        const dialog = pageStack.push(Qt.resolvedUrl("RemovePinDialog.qml"));
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
            if (page.pending === "")
                return;
            page.pending = "";
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
            DetailItem {
                objectName: "lockMethod"
                label: qsTr("Lock method")
                value: SettingsController.authModeLabel(Security.authMode)
            }
            ActionItem {
                objectName: "pinItem"
                text: Security.hasQuickPIN ? qsTr("Change quick PIN") : qsTr("Set quick PIN")
                enabled: page.pending === ""
                onClicked: page.openPinDialog()
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
                text: qsTr("Status")
            }
            DetailItem {
                objectName: "fingerprint"
                label: qsTr("Fingerprint")
                value: Security.fingerprintAvailable ? qsTr("Enrolled") : qsTr("Not enrolled")
            }
            DetailItem {
                objectName: "failedAttempts"
                label: qsTr("Failed attempts")
                value: String(Security.failedAttempts)
            }
            DetailItem {
                objectName: "accountStatus"
                label: qsTr("Account")
                value: SettingsController.lockoutStatusText(Security.isLockedOut, Security.lockoutSecondsRemaining)
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
                text: qsTr("Your system password (PAM) always unlocks the device. The quick PIN is an optional shortcut, stored encrypted. Fingerprints are handled by fprintd. Failed attempts are rate limited to 5, with a growing lockout, and logged.")
            }
        }

        VerticalScrollDecorator {}
    }
}
