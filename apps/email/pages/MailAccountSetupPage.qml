pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Classic-password IMAP/SMTP account setup. Reached from the no-account
// state on EmailApp.qml's inbox via "Sign in with IMAP". This is the
// shipping path for any provider that doesn't speak OAuth (Fastmail,
// self-hosted IMAP, work mail behind app-passwords).
//
// Provider preset hint: tapping Fastmail/iCloud chips below pre-fills the
// IMAP/SMTP host + port pair for the major password-IMAP providers, so
// the user only ever enters email + app-password.
Page {
    id: page

    signal back
    signal accountCreated(string accountId)

    readonly property var mail: typeof MailService !== "undefined" ? MailService : null

    // Form state — bound to TextField text.
    property string formName: ""
    property string formEmail: ""
    property string formImapHost: ""
    property int formImapPort: 993
    property int formImapEnc: 1  // 0=none, 1=SSL, 2=STARTTLS
    property string formSmtpHost: ""
    property int formSmtpPort: 465
    property int formSmtpEnc: 1
    property string formUsername: ""
    property string formPassword: ""
    property bool busy: false
    property string lastError: ""

    background: Rectangle {
        color: MColors.background
    }

    function applyPreset(presetId) {
        if (presetId === "fastmail") {
            page.formImapHost = "imap.fastmail.com";
            page.formImapPort = 993;
            page.formImapEnc = 1;
            page.formSmtpHost = "smtp.fastmail.com";
            page.formSmtpPort = 465;
            page.formSmtpEnc = 1;
        } else if (presetId === "icloud") {
            page.formImapHost = "imap.mail.me.com";
            page.formImapPort = 993;
            page.formImapEnc = 1;
            page.formSmtpHost = "smtp.mail.me.com";
            page.formSmtpPort = 587;
            page.formSmtpEnc = 2;
        } else if (presetId === "yahoo") {
            page.formImapHost = "imap.mail.yahoo.com";
            page.formImapPort = 993;
            page.formImapEnc = 1;
            page.formSmtpHost = "smtp.mail.yahoo.com";
            page.formSmtpPort = 465;
            page.formSmtpEnc = 1;
        }
    }

    MActionBar {
        id: actionBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        backLabel: "Mail"
        onBackClicked: page.back()
    }

    Flickable {
        anchors.top: actionBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: col.implicitHeight + MSpacing.xl
        clip: true

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: MSpacing.lg
            anchors.rightMargin: MSpacing.lg
            anchors.topMargin: MSpacing.md
            spacing: MSpacing.md

            Text {
                text: "Add mail account"
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeTitle3
                font.weight: MTypography.weightLight
                font.letterSpacing: MTypography.trackingTitle3
            }
            Text {
                width: parent.width
                text: "For Fastmail, iCloud, and other providers that don't use OAuth. Use an app-specific password if your provider requires one."
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                wrapMode: Text.WordWrap
            }

            // Preset chips — single tap pre-fills imap/smtp host+port.
            Row {
                spacing: MSpacing.sm
                MButton {
                    text: "Fastmail"
                    onClicked: page.applyPreset("fastmail")
                }
                MButton {
                    text: "iCloud"
                    onClicked: page.applyPreset("icloud")
                }
                MButton {
                    text: "Yahoo"
                    onClicked: page.applyPreset("yahoo")
                }
            }

            // Identity.
            Label {
                text: "Your name"
                color: MColors.textSecondary
            }
            TextField {
                width: parent.width
                placeholderText: "Patrick Q."
                text: page.formName
                onTextChanged: page.formName = text
            }

            Label {
                text: "Email address"
                color: MColors.textSecondary
            }
            TextField {
                width: parent.width
                placeholderText: "you@example.com"
                inputMethodHints: Qt.ImhEmailCharactersOnly
                text: page.formEmail
                onTextChanged: {
                    page.formEmail = text;
                    // Default username to email if user hasn't customised.
                    if (page.formUsername === "" || page.formUsername === text.substring(0, text.indexOf("@")))
                        page.formUsername = text;
                }
            }

            // IMAP.
            Text {
                text: "INCOMING (IMAP)"
                color: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightBold
                font.letterSpacing: MTypography.trackingEyebrow
                font.capitalization: Font.AllUppercase
            }
            Label {
                text: "Host"
                color: MColors.textSecondary
            }
            TextField {
                width: parent.width
                placeholderText: "imap.example.com"
                text: page.formImapHost
                onTextChanged: page.formImapHost = text
            }
            Row {
                spacing: MSpacing.md
                Column {
                    spacing: 2
                    Label {
                        text: "Port"
                        color: MColors.textSecondary
                    }
                    TextField {
                        width: 100
                        placeholderText: "993"
                        inputMethodHints: Qt.ImhDigitsOnly
                        text: page.formImapPort > 0 ? String(page.formImapPort) : ""
                        onTextChanged: page.formImapPort = parseInt(text) || 0
                    }
                }
                Column {
                    spacing: 2
                    Label {
                        text: "Security"
                        color: MColors.textSecondary
                    }
                    Row {
                        spacing: MSpacing.xs
                        MButton {
                            text: "SSL"
                            variant: page.formImapEnc === 1 ? "primary" : "secondary"
                            onClicked: {
                                page.formImapEnc = 1;
                                page.formImapPort = 993;
                            }
                        }
                        MButton {
                            text: "TLS"
                            variant: page.formImapEnc === 2 ? "primary" : "secondary"
                            onClicked: {
                                page.formImapEnc = 2;
                                page.formImapPort = 143;
                            }
                        }
                        MButton {
                            text: "None"
                            variant: page.formImapEnc === 0 ? "primary" : "secondary"
                            onClicked: {
                                page.formImapEnc = 0;
                                page.formImapPort = 143;
                            }
                        }
                    }
                }
            }

            // SMTP.
            Text {
                text: "OUTGOING (SMTP)"
                color: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightBold
                font.letterSpacing: MTypography.trackingEyebrow
                font.capitalization: Font.AllUppercase
            }
            Label {
                text: "Host"
                color: MColors.textSecondary
            }
            TextField {
                width: parent.width
                placeholderText: "smtp.example.com"
                text: page.formSmtpHost
                onTextChanged: page.formSmtpHost = text
            }
            Row {
                spacing: MSpacing.md
                Column {
                    spacing: 2
                    Label {
                        text: "Port"
                        color: MColors.textSecondary
                    }
                    TextField {
                        width: 100
                        placeholderText: "465"
                        inputMethodHints: Qt.ImhDigitsOnly
                        text: page.formSmtpPort > 0 ? String(page.formSmtpPort) : ""
                        onTextChanged: page.formSmtpPort = parseInt(text) || 0
                    }
                }
                Column {
                    spacing: 2
                    Label {
                        text: "Security"
                        color: MColors.textSecondary
                    }
                    Row {
                        spacing: MSpacing.xs
                        MButton {
                            text: "SSL"
                            variant: page.formSmtpEnc === 1 ? "primary" : "secondary"
                            onClicked: {
                                page.formSmtpEnc = 1;
                                page.formSmtpPort = 465;
                            }
                        }
                        MButton {
                            text: "TLS"
                            variant: page.formSmtpEnc === 2 ? "primary" : "secondary"
                            onClicked: {
                                page.formSmtpEnc = 2;
                                page.formSmtpPort = 587;
                            }
                        }
                        MButton {
                            text: "None"
                            variant: page.formSmtpEnc === 0 ? "primary" : "secondary"
                            onClicked: {
                                page.formSmtpEnc = 0;
                                page.formSmtpPort = 25;
                            }
                        }
                    }
                }
            }

            // Auth.
            Text {
                text: "AUTHENTICATION"
                color: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightBold
                font.letterSpacing: MTypography.trackingEyebrow
                font.capitalization: Font.AllUppercase
            }
            Label {
                text: "Username"
                color: MColors.textSecondary
            }
            TextField {
                width: parent.width
                placeholderText: "Usually your email address"
                text: page.formUsername
                onTextChanged: page.formUsername = text
            }
            Label {
                text: "Password / app-password"
                color: MColors.textSecondary
            }
            TextField {
                width: parent.width
                placeholderText: "••••••••"
                echoMode: TextInput.Password
                text: page.formPassword
                onTextChanged: page.formPassword = text
            }

            // Error strip.
            Text {
                width: parent.width
                visible: page.lastError !== ""
                text: page.lastError
                color: MColors.error
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                wrapMode: Text.WordWrap
            }

            // Submit / cancel.
            Row {
                spacing: MSpacing.md
                anchors.right: parent.right
                MButton {
                    text: "Cancel"
                    onClicked: page.back()
                }
                MButton {
                    text: page.busy ? "Adding…" : "Add account"
                    variant: "primary"
                    disabled: page.busy || page.formEmail.length === 0 || page.formImapHost.length === 0 || page.formSmtpHost.length === 0 || page.formUsername.length === 0 || page.formPassword.length === 0
                    onClicked: {
                        if (!page.mail) {
                            page.lastError = "Mail service unavailable.";
                            return;
                        }
                        page.busy = true;
                        page.lastError = "";
                        const id = page.mail.addImapAccount(page.formName.length > 0 ? page.formName : page.formEmail, page.formEmail, page.formImapHost, page.formImapPort, page.formImapEnc, page.formSmtpHost, page.formSmtpPort, page.formSmtpEnc, page.formUsername, page.formPassword);
                        page.busy = false;
                        if (id && id.length > 0) {
                            page.formPassword = "";
                            page.accountCreated(id);
                        } else {
                            page.lastError = "Could not save account. Check fields and try again.";
                        }
                    }
                }
            }

            Item {
                width: 1
                height: MSpacing.xl
            }
        }
    }
}
