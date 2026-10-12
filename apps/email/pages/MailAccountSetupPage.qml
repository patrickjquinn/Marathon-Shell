pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

// Classic-password IMAP/SMTP account for providers without OAuth.
Dialog {
    id: page

    property var app
    readonly property var mail: app.mail
    property string provider: ""
    property int imapEnc: 1
    property int smtpEnc: 1
    property bool busy: false
    property bool signedIn: false
    property string lastError: ""

    readonly property string email: emailField.text.trim()
    readonly property bool emailValid: Logic.emailValid(email)
    readonly property bool canSubmit: !busy && emailValid && passwordField.text.length > 0
    readonly property bool hasServers: imapHostField.text.trim() !== "" && smtpHostField.text.trim() !== ""

    function applyPreset(id) {
        provider = id;
        providerBox.currentIndex = Logic.providers.indexOf(id);
        const p = Logic.presets[id];
        if (!p) {
            serverSwitch.checked = true;
            return;
        }
        imapHostField.text = p.imapHost;
        imapPortField.text = String(p.imapPort);
        imapEnc = p.imapEnc;
        smtpHostField.text = p.smtpHost;
        smtpPortField.text = String(p.smtpPort);
        smtpEnc = p.smtpEnc;
    }

    function askForServers() {
        serverSwitch.checked = true;
        lastError = qsTr("Enter your provider's incoming and outgoing server names. Their help pages list them.");
    }

    function submit() {
        lastError = "";
        if (!hasServers) {
            askForServers();
            return;
        }
        const name = nameField.text.trim();
        const user = usernameField.text.trim();
        busy = mail.addImapAccount(name || email, email, imapHostField.text.trim(), parseInt(imapPortField.text) || 0, imapEnc, smtpHostField.text.trim(), parseInt(smtpPortField.text) || 0, smtpEnc, user || email, passwordField.text);
        if (!busy)
            lastError = qsTr("Couldn't start signing in. Close Mail and open it again, then try again.");
    }

    canAccept: canSubmit && hasServers
    acceptDestination: signingIn
    onAcceptBlocked: {
        if (busy)
            return;
        if (canSubmit)
            askForServers();
        else
            Notices.show(emailValid ? qsTr("Enter your password") : qsTr("Enter your email address"));
    }
    onAccepted: submit()
    Component.onDestruction: if (busy)
        mail.cancelAccountSetup()

    Connections {
        target: page.mail
        ignoreUnknownSignals: true
        function onAccountSetupSucceeded(accountId) {
            page.signedIn = true;
            page.busy = false;
            passwordField.text = "";
            page.app.showInbox();
        }
        function onAccountSetupFailed(reason) {
            page.busy = false;
            if (reason !== "cancelled")
                page.lastError = Logic.setupFailureText(reason);
        }
    }

    Component {
        id: signingIn

        Page {
            id: waitPage

            // A failure or a cancel returns to the form with its fields kept.
            function leaveIfDone() {
                if (!page.busy && !page.signedIn && status === PageStatus.Active && page.status === PageStatus.Inactive)
                    pageStack.pop();
            }

            objectName: "signingInPage"
            onStatusChanged: {
                if (status === PageStatus.Deactivating && page.busy)
                    page.mail.cancelAccountSetup();
                leaveIfDone();
            }

            Connections {
                target: page
                function onBusyChanged() {
                    waitPage.leaveIfDone();
                }
                function onStatusChanged() {
                    waitPage.leaveIfDone();
                }
            }

            SilicaFlickable {
                anchors.fill: parent

                PullDownMenu {
                    MenuItem {
                        objectName: "cancelItem"
                        text: qsTr("Cancel sign-in")
                        onClicked: page.mail.cancelAccountSetup()
                    }
                }

                BusyLabel {
                    running: true
                    text: qsTr("Signing in")
                }
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Sign in")
                title: qsTr("Other (IMAP)")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                text: qsTr("If your provider uses two-step sign-in, create an app password on their website and use it here.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
            ComboBox {
                id: providerBox

                objectName: "providerBox"
                label: qsTr("Provider")
                currentIndex: Logic.providers.indexOf("other")
                menu: ContextMenu {
                    Repeater {
                        model: [qsTr("Fastmail"), qsTr("iCloud"), qsTr("Yahoo"), qsTr("Other")]

                        MenuItem {
                            required property string modelData
                            required property int index

                            text: modelData
                            onClicked: page.applyPreset(Logic.providers[index])
                        }
                    }
                }
            }
            TextField {
                id: emailField

                objectName: "emailField"
                width: parent.width
                label: qsTr("Email address")
                placeholderText: qsTr("you@example.com")
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                errorHighlight: page.email !== "" && !page.emailValid && !activeFocus
                description: errorHighlight ? qsTr("Enter a full email address, like name@example.com") : ""
                onTextChanged: {
                    const preset = Logic.presetForEmail(text);
                    if (preset !== "" && preset !== page.provider)
                        page.applyPreset(preset);
                }
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordField.focus = true
            }
            PasswordField {
                id: passwordField

                objectName: "passwordField"
                width: parent.width
                label: qsTr("Password")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: nameField.focus = true
            }
            TextField {
                id: nameField

                objectName: "nameField"
                width: parent.width
                label: qsTr("Your name")
                placeholderText: qsTr("Your name (optional)")
                description: qsTr("Shown to people you write to")
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
            TextSwitch {
                id: serverSwitch

                objectName: "serverSwitch"
                text: qsTr("Server settings")
                description: qsTr("Filled in for you for Fastmail, iCloud and Yahoo")
            }

            Column {
                objectName: "serverSettings"
                width: parent.width
                visible: serverSwitch.checked

                SectionHeader {
                    text: qsTr("Incoming server (IMAP)")
                }
                TextField {
                    id: imapHostField

                    objectName: "imapHostField"
                    width: parent.width
                    label: qsTr("Server")
                    placeholderText: qsTr("imap.example.com")
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                }
                TextField {
                    id: imapPortField

                    objectName: "imapPortField"
                    width: parent.width
                    label: qsTr("Port")
                    text: "993"
                    inputMethodHints: Qt.ImhDigitsOnly
                }
                ComboBox {
                    objectName: "imapEncBox"
                    label: qsTr("Encryption")
                    currentIndex: Logic.encryptions.indexOf(page.imapEnc)
                    menu: ContextMenu {
                        Repeater {
                            model: [qsTr("SSL"), qsTr("STARTTLS"), qsTr("None")]

                            MenuItem {
                                required property string modelData
                                required property int index

                                text: modelData
                                onClicked: {
                                    page.imapEnc = Logic.encryptions[index];
                                    imapPortField.text = String(Logic.imapPorts[page.imapEnc]);
                                }
                            }
                        }
                    }
                }

                SectionHeader {
                    text: qsTr("Outgoing server (SMTP)")
                }
                TextField {
                    id: smtpHostField

                    objectName: "smtpHostField"
                    width: parent.width
                    label: qsTr("Server")
                    placeholderText: qsTr("smtp.example.com")
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                }
                TextField {
                    id: smtpPortField

                    objectName: "smtpPortField"
                    width: parent.width
                    label: qsTr("Port")
                    text: "465"
                    inputMethodHints: Qt.ImhDigitsOnly
                }
                ComboBox {
                    objectName: "smtpEncBox"
                    label: qsTr("Encryption")
                    currentIndex: Logic.encryptions.indexOf(page.smtpEnc)
                    menu: ContextMenu {
                        Repeater {
                            model: [qsTr("SSL"), qsTr("STARTTLS"), qsTr("None")]

                            MenuItem {
                                required property string modelData
                                required property int index

                                text: modelData
                                onClicked: {
                                    page.smtpEnc = Logic.encryptions[index];
                                    smtpPortField.text = String(Logic.smtpPorts[page.smtpEnc]);
                                }
                            }
                        }
                    }
                }
                TextField {
                    id: usernameField

                    objectName: "usernameField"
                    width: parent.width
                    label: qsTr("Username")
                    placeholderText: qsTr("Username (same as email address)")
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                }
            }

            Label {
                objectName: "error"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                visible: page.lastError !== ""
                text: page.lastError
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.errorColor
            }
        }

        VerticalScrollDecorator {}
    }
}
