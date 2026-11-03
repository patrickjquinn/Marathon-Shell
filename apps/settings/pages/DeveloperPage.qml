pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property bool remoteOn: Security.remoteConnection === "on"
    readonly property bool passwordOk: passwordField.text.length >= 8
    // The shell keeps only the password's hash: this is the one set while
    // the page is open.
    property string applied: ""
    // Waiting for the shell to turn remote connection "on" or "off".
    property string pending: ""
    property var addresses: []
    readonly property string user: Security.currentUsername()

    function refreshAddresses() {
        addresses = SettingsController.remoteAddresses();
    }

    function apply(on, pin) {
        pending = on ? "on" : "off";
        Security.setRemoteConnection(on, on ? passwordField.text : "", pin);
    }

    // Turning on and a new password take the quick PIN, where there is one.
    function allow() {
        if (!Security.hasQuickPIN)
            return apply(true, "");
        const dialog = pageStack.push(Qt.resolvedUrl("RemotePinDialog.qml"));
        dialog.accepted.connect(() => page.apply(true, dialog.pin));
    }

    onStatusChanged: {
        if (status === PageStatus.Active)
            refreshAddresses();
    }
    Component.onCompleted: {
        if (!remoteOn)
            passwordField.text = SettingsController.newRemotePassword();
    }

    Connections {
        target: Security

        function onRemoteConnectionApplied() {
            if (page.pending === "on")
                page.applied = passwordField.text;
            page.pending = "";
            page.refreshAddresses();
        }
        function onRemoteConnectionFailed(reason) {
            page.pending = "";
            Notices.show(reason);
        }
    }

    Connections {
        target: Network

        function onWifiConnectedChanged() {
            page.refreshAddresses();
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "generateItem"
                text: qsTr("Generate password")
                onClicked: passwordField.text = SettingsController.newRemotePassword()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Developer tools")
            }
            TextSwitch {
                objectName: "remoteSwitch"
                text: qsTr("Remote connection")
                description: qsTr("Log in over SSH from a computer on the same USB cable or network")
                automaticCheck: false
                checked: page.remoteOn
                busy: page.pending !== ""
                enabled: page.pending === "" && (page.remoteOn || page.passwordOk)
                onClicked: page.remoteOn ? page.apply(false, "") : page.allow()
            }
            PasswordField {
                id: passwordField

                objectName: "passwordField"
                width: parent.width
                label: qsTr("Password")
                placeholderText: page.remoteOn ? qsTr("New password") : label
                description: !page.passwordOk && (text !== "" || !page.remoteOn) ? qsTr("At least 8 characters") : page.remoteOn ? qsTr("Type a new password and save it to change it") : qsTr("You log in as %1 with this password. Change it if you like.").arg(page.user)
                errorHighlight: text !== "" && !page.passwordOk
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
            Button {
                objectName: "saveButton"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.remoteOn
                enabled: page.pending === "" && page.passwordOk && passwordField.text !== page.applied
                text: qsTr("Save password")
                onClicked: page.allow()
            }
            Label {
                objectName: "warning"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                text: qsTr("Anyone with this password who can reach your phone over USB or a network can read and change everything on it, and the password unlocks your phone too. Turn remote connection off when you're not using it.")
            }

            SectionHeader {
                text: qsTr("Connect")
                visible: page.remoteOn
            }
            Repeater {
                model: page.remoteOn ? page.addresses : []

                DetailItem {
                    required property var modelData

                    label: Logic.remoteAddressLabel(modelData.kind)
                    value: modelData.address
                }
            }
            Label {
                objectName: "connectHint"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.remoteOn
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.addresses.length > 0 ? qsTr("On the computer, run ssh %1@%2").arg(page.user).arg(page.addresses[0].address) : qsTr("Connect a USB cable or join a Wi-Fi network to get an address.")
            }
        }

        VerticalScrollDecorator {}
    }
}
