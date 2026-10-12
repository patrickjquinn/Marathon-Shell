pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Controls
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
// Known providers fill the server settings from the email domain or a
// provider chip, so the user only enters email + app password. Server
// settings stay collapsed unless the provider is unknown.
Page {
    id: page

    signal back
    signal accountCreated(string accountId)

    readonly property var mail: typeof MailService !== "undefined" ? MailService : null

    readonly property var presets: ({
            "fastmail": {
                "imapHost": "imap.fastmail.com",
                "imapPort": 993,
                "imapEnc": 1,
                "smtpHost": "smtp.fastmail.com",
                "smtpPort": 465,
                "smtpEnc": 1
            },
            "icloud": {
                "imapHost": "imap.mail.me.com",
                "imapPort": 993,
                "imapEnc": 1,
                "smtpHost": "smtp.mail.me.com",
                "smtpPort": 587,
                "smtpEnc": 2
            },
            "yahoo": {
                "imapHost": "imap.mail.yahoo.com",
                "imapPort": 993,
                "imapEnc": 1,
                "smtpHost": "smtp.mail.yahoo.com",
                "smtpPort": 465,
                "smtpEnc": 1
            }
        })
    readonly property var domainPresets: ({
            "fastmail.com": "fastmail",
            "fastmail.fm": "fastmail",
            "icloud.com": "icloud",
            "me.com": "icloud",
            "mac.com": "icloud",
            "yahoo.com": "yahoo",
            "ymail.com": "yahoo"
        })

    property string provider: ""
    property bool showServerSettings: false
    property int imapEnc: 1  // 0=none, 1=SSL, 2=STARTTLS
    property int smtpEnc: 1
    property bool busy: false
    property string lastError: ""

    readonly property string email: emailField.text.trim()
    readonly property bool emailValid: /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)
    readonly property bool canSubmit: !busy && emailValid && passwordField.text.length > 0

    function applyPreset(presetId) {
        provider = presetId;
        const p = presets[presetId];
        if (!p) {
            showServerSettings = true;
            return;
        }
        imapHostField.text = p.imapHost;
        imapPortField.text = String(p.imapPort);
        imapEnc = p.imapEnc;
        smtpHostField.text = p.smtpHost;
        smtpPortField.text = String(p.smtpPort);
        smtpEnc = p.smtpEnc;
    }

    function submit() {
        lastError = "";
        if (imapHostField.text.trim() === "" || smtpHostField.text.trim() === "") {
            showServerSettings = true;
            lastError = "Enter your provider's incoming and outgoing server names. Their help pages list them.";
            return;
        }
        busy = true;
        // Defer so the busy state paints before the blocking add call.
        addTimer.start();
    }

    background: Rectangle {
        color: MColors.background
    }

    Timer {
        id: addTimer
        interval: 50
        onTriggered: {
            const id = page.mail ? page.mail.addImapAccount(nameField.text.trim() !== "" ? nameField.text.trim() : page.email, page.email, imapHostField.text.trim(), parseInt(imapPortField.text) || 0, page.imapEnc, smtpHostField.text.trim(), parseInt(smtpPortField.text) || 0, page.smtpEnc, usernameField.text.trim() !== "" ? usernameField.text.trim() : page.email, passwordField.text) : "";
            page.busy = false;
            if (id !== "") {
                passwordField.text = "";
                page.accountCreated(id);
            } else if (!page.mail) {
                page.lastError = "Mail isn't available right now. Close Mail and open it again.";
            } else {
                page.lastError = "Couldn't sign in. Check your email address and password — many providers need an app password here — and the server settings, then try again.";
            }
        }
    }

    MTopBar {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        title: "Add account"
        showBack: true
        onBackClicked: page.back()
    }

    Flickable {
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: col.implicitHeight + MSpacing.xl * 2
        clip: true

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: MSpacing.lg
            anchors.rightMargin: MSpacing.lg
            anchors.topMargin: MSpacing.md
            spacing: MSpacing.md

            Text {
                width: parent.width
                text: "For Fastmail, iCloud, Yahoo and other providers. If your provider uses two-step sign-in, create an app password on their website and use it here."
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                wrapMode: Text.WordWrap
            }

            Flow {
                width: parent.width
                spacing: MSpacing.sm

                Repeater {
                    model: [
                        {
                            "id": "fastmail",
                            "label": "Fastmail"
                        },
                        {
                            "id": "icloud",
                            "label": "iCloud"
                        },
                        {
                            "id": "yahoo",
                            "label": "Yahoo"
                        },
                        {
                            "id": "other",
                            "label": "Other"
                        }
                    ]

                    MButton {
                        required property var modelData
                        text: modelData.label
                        size: "compact"
                        variant: page.provider === modelData.id ? "primary" : "secondary"
                        onClicked: page.applyPreset(modelData.id)
                    }
                }
            }

            MTextField {
                id: emailField
                width: parent.width
                label: "Email address"
                placeholder: "you@example.com"
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                errorText: page.email !== "" && !page.emailValid && !emailField.focused ? "Enter a full email address, like name@example.com." : ""
                onTextChanged: {
                    const domain = text.split("@")[1] || "";
                    const preset = page.domainPresets[domain.trim().toLowerCase()];
                    if (preset && preset !== page.provider)
                        page.applyPreset(preset);
                }
            }

            MTextField {
                id: passwordField
                width: parent.width
                label: "Password or app password"
                echoMode: TextInput.Password
            }

            MTextField {
                id: nameField
                width: parent.width
                label: "Your name (shown to recipients)"
                placeholder: "Optional"
            }

            Item {
                width: parent.width
                height: Math.round(44 * Constants.scaleFactor)

                Accessible.role: Accessible.Button
                Accessible.name: page.showServerSettings ? "Hide server settings" : "Show server settings"
                Accessible.onPressAction: page.showServerSettings = !page.showServerSettings

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Server settings"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeBody
                    font.weight: MTypography.weightMedium
                }
                Icon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: page.showServerSettings ? "caret-up" : "caret-down"
                    size: 18
                    color: MColors.textSecondary
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.showServerSettings = !page.showServerSettings
                }
            }

            Column {
                width: parent.width
                spacing: MSpacing.md
                visible: page.showServerSettings

                Text {
                    text: "INCOMING (IMAP)"
                    color: MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightBold
                    font.letterSpacing: MTypography.trackingEyebrow
                }
                MTextField {
                    id: imapHostField
                    width: parent.width
                    label: "Server"
                    placeholder: "imap.example.com"
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                }
                Row {
                    width: parent.width
                    spacing: MSpacing.sm

                    MTextField {
                        id: imapPortField
                        width: Math.round(96 * Constants.scaleFactor)
                        label: "Port"
                        text: "993"
                        inputMethodHints: Qt.ImhDigitsOnly
                    }
                    Repeater {
                        model: [
                            {
                                "enc": 1,
                                "label": "SSL",
                                "port": 993
                            },
                            {
                                "enc": 2,
                                "label": "STARTTLS",
                                "port": 143
                            },
                            {
                                "enc": 0,
                                "label": "None",
                                "port": 143
                            }
                        ]

                        MButton {
                            required property var modelData
                            anchors.bottom: parent.bottom
                            text: modelData.label
                            size: "compact"
                            variant: page.imapEnc === modelData.enc ? "primary" : "secondary"
                            onClicked: {
                                page.imapEnc = modelData.enc;
                                imapPortField.text = String(modelData.port);
                            }
                        }
                    }
                }

                Text {
                    text: "OUTGOING (SMTP)"
                    color: MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightBold
                    font.letterSpacing: MTypography.trackingEyebrow
                }
                MTextField {
                    id: smtpHostField
                    width: parent.width
                    label: "Server"
                    placeholder: "smtp.example.com"
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                }
                Row {
                    width: parent.width
                    spacing: MSpacing.sm

                    MTextField {
                        id: smtpPortField
                        width: Math.round(96 * Constants.scaleFactor)
                        label: "Port"
                        text: "465"
                        inputMethodHints: Qt.ImhDigitsOnly
                    }
                    Repeater {
                        model: [
                            {
                                "enc": 1,
                                "label": "SSL",
                                "port": 465
                            },
                            {
                                "enc": 2,
                                "label": "STARTTLS",
                                "port": 587
                            },
                            {
                                "enc": 0,
                                "label": "None",
                                "port": 25
                            }
                        ]

                        MButton {
                            required property var modelData
                            anchors.bottom: parent.bottom
                            text: modelData.label
                            size: "compact"
                            variant: page.smtpEnc === modelData.enc ? "primary" : "secondary"
                            onClicked: {
                                page.smtpEnc = modelData.enc;
                                smtpPortField.text = String(modelData.port);
                            }
                        }
                    }
                }

                MTextField {
                    id: usernameField
                    width: parent.width
                    label: "Username"
                    placeholder: "Same as email address"
                    inputMethodHints: Qt.ImhNoAutoUppercase
                }
            }

            Text {
                width: parent.width
                visible: page.lastError !== ""
                text: page.lastError
                color: MColors.error
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                wrapMode: Text.WordWrap
            }

            MButton {
                width: parent.width
                text: page.busy ? "Signing in…" : "Add account"
                variant: "primary"
                controlState: page.busy ? "loading" : "default"
                disabled: !page.canSubmit
                onClicked: page.submit()
            }

            Text {
                width: parent.width
                visible: page.busy
                text: "Checking your account. This can take a few seconds."
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
