import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Lists
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "pages"

// Mail — native inbox bound to MailService (QMF backend).
//
// Day 10 wire-up: the inbox + message viewer + compose sheet are
// orchestrated via a single StackView. Each page brings its own
// chrome (top bar / action bar / tab bar). Push transitions match the
// shell's standard horizontal slide.
//
// Page contract:
//   inboxPage     emit messageOpenRequested(messageId)
//                       → stack.push(messagePage, { messageId })
//   messagePage   emit back                  → stack.pop()
//                 emit replyRequested(prefill) → stack.push(composePage, prefill)
//   composePage   emit back                  → stack.pop()
//                 emit sent                  → stack.pop() (already pops on its own,
//                                              we just refresh inbox after)
//
// Hard rule (Marathon coding): NO PLACEHOLDER MAIL. Three honest states
// stay in the inbox component: service-unavailable, no-account, or
// Inbox-zero + real ListView bound to MailService.messages.
MApp {
    id: emailApp

    readonly property var mail: typeof MailService !== "undefined" ? MailService : null
    // QMF backend bootstrapped successfully. mail.accounts is null when
    // MailService's ctor couldn't reach QMailStore (first boot before
    // messageserver inits, missing storage dir, etc.) — treat as
    // unavailable and show the service-unavailable state instead of
    // touching the dead backend and crashing.
    readonly property bool serviceAvailable: mail !== null && mail.accounts !== null

    Rectangle {
        anchors.fill: parent
        color: MColors.background
    }

    MStackView {
        id: navigationStack
        anchors.fill: parent
        initialItem: inboxComponent
    }

    // ── Inbox page ─────────────────────────────────────────────────
    Component {
        id: inboxComponent

        Item {
            id: inboxPage

            signal messageOpenRequested(string messageId)

            readonly property int accountCount: emailApp.serviceAvailable && emailApp.mail.accounts ? (emailApp.mail.accounts.rowCount ? emailApp.mail.accounts.rowCount() : 0) : 0
            readonly property int messageCount: emailApp.serviceAvailable && emailApp.mail.messages ? (emailApp.mail.messages.rowCount ? emailApp.mail.messages.rowCount() : 0) : 0

            // OAuth flow status surfaced under the Sign-in buttons.
            // Updated from the Connections block below as the helper
            // progresses through bind-loopback / open-browser / success.
            property string oauthMessage: ""
            property bool oauthError: false

            // Listen for the OAuth-flow signals from MailService. The
            // helper is async (it blocks on the loopback redirect from
            // the browser), so the QML side just relays state to UI.
            Connections {
                target: emailApp.mail
                ignoreUnknownSignals: true
                function onOauthAuthUrlReady(url) {
                    inboxPage.oauthMessage = "Continue in your browser…";
                    inboxPage.oauthError = false;
                    Qt.openUrlExternally(url);
                }
                function onOauthLoginSucceeded(accountId) {
                    inboxPage.oauthMessage = "";
                    inboxPage.oauthError = false;
                }
                function onOauthLoginFailed(code, message) {
                    if (code === "oauth_not_configured") {
                        inboxPage.oauthMessage = "OAuth sign-in isn't enabled in this build. Use Sign in with IMAP instead.";
                    } else {
                        inboxPage.oauthMessage = message;
                    }
                    inboxPage.oauthError = true;
                }
            }

            MTopBar {
                id: topBar
                title: "Inbox"
                showBack: false
            }

            Item {
                id: content
                anchors {
                    top: topBar.bottom
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }

                // State 1 — MailService not available.
                Item {
                    anchors.fill: parent
                    visible: !emailApp.serviceAvailable

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - MSpacing.xl * 2
                        spacing: MSpacing.md
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            name: "envelope"
                            size: 48
                            color: MColors.textTertiary
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Mail service unavailable"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeHeadline
                            font.weight: MTypography.weightDemiBold
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: "QMF (the mail backend) is not running. Restart the device or check `systemctl --user status marathon-mailserver.service`."
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // State 2 — no account configured.
                Item {
                    anchors.fill: parent
                    visible: emailApp.serviceAvailable && inboxPage.accountCount === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - MSpacing.xl * 2
                        spacing: MSpacing.md
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            name: "envelope-plus"
                            size: 48
                            color: MColors.textTertiary
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Add a mail account"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeTitle3
                            font.weight: MTypography.weightLight
                            font.letterSpacing: MTypography.trackingTitle3
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: "Sign in with Gmail or Outlook. Your password never touches Marathon — only an OAuth refresh token stored in your keyring."
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        MButton {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: MSpacing.sm
                            text: "Sign in with Google"
                            variant: "primary"
                            onClicked: {
                                if (emailApp.mail)
                                    emailApp.mail.startOAuthLogin("gmail");
                            }
                        }
                        MButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Sign in with Microsoft"
                            variant: "secondary"
                            onClicked: {
                                if (emailApp.mail)
                                    emailApp.mail.startOAuthLogin("outlook");
                            }
                        }
                        MButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Sign in with IMAP"
                            variant: "secondary"
                            onClicked: navigationStack.push(setupComponent)
                        }

                        // OAuth flow feedback. The buttons above are
                        // fire-and-forget — the helper runs async, so
                        // we surface progress here.
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            visible: inboxPage.oauthMessage !== ""
                            text: inboxPage.oauthMessage
                            color: inboxPage.oauthError ? MColors.error : MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // State 3 — account configured.
                Item {
                    anchors.fill: parent
                    visible: emailApp.serviceAvailable && inboxPage.accountCount > 0

                    RowLayout {
                        id: captionRow
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            topMargin: 8
                            leftMargin: MSpacing.lg
                            rightMargin: MSpacing.lg
                        }
                        spacing: MSpacing.md

                        Text {
                            text: {
                                if (!emailApp.serviceAvailable)
                                    return "";
                                const unread = emailApp.mail.unreadCount;
                                const total = inboxPage.messageCount;
                                if (unread > 0)
                                    return unread + " unread · " + total + " total";
                                return total + " total";
                            }
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: MTypography.weightBold
                            font.letterSpacing: MTypography.trackingEyebrow
                            font.capitalization: Font.AllUppercase
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                        }
                        Text {
                            text: "Sort: Newest"
                            color: MColors.marathonTealBright
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: MTypography.weightBold
                            font.letterSpacing: MTypography.trackingEyebrow
                            font.capitalization: Font.AllUppercase
                        }
                    }

                    // Inbox-zero.
                    Item {
                        anchors.fill: parent
                        anchors.topMargin: captionRow.height + 8
                        visible: inboxPage.messageCount === 0
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: MSpacing.sm
                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                name: "check"
                                size: 36
                                color: MColors.marathonTealBright
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Inbox zero"
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeHeadline
                                font.weight: MTypography.weightLight
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: emailApp.mail.syncState === "syncing" ? "Syncing…" : "All caught up."
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                            }
                        }
                    }

                    ListView {
                        id: messageList
                        visible: inboxPage.messageCount > 0
                        anchors {
                            top: captionRow.bottom
                            topMargin: 8
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        clip: true
                        model: emailApp.mail ? emailApp.mail.messages : null
                        delegate: Item {
                            width: messageList.width
                            height: rowContent.implicitHeight + 24

                            Rectangle {
                                anchors.fill: parent
                                color: model.unread ? Qt.rgba(0, 191 / 255, 165 / 255, 0.025) : "transparent"
                            }
                            Rectangle {
                                visible: model.unread
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3
                                color: MColors.marathonTealBright
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: MColors.whiteOverlay04
                            }

                            Row {
                                id: rowContent
                                anchors.fill: parent
                                anchors.leftMargin: MSpacing.lg
                                anchors.rightMargin: MSpacing.lg
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: 14

                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: MRadius.md
                                    color: model.tint || MColors.bb10Card
                                    border.width: 1
                                    border.color: MColors.whiteOverlay08
                                    Text {
                                        anchors.centerIn: parent
                                        text: (model.from || "?").substring(0, 1).toUpperCase()
                                        color: "#ffffff"
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        font.weight: MTypography.weightDemiBold
                                    }
                                }

                                Column {
                                    width: rowContent.width - 36 - 14
                                    spacing: 2
                                    Item {
                                        width: parent.width
                                        height: fromText.implicitHeight
                                        Text {
                                            id: fromText
                                            anchors.left: parent.left
                                            anchors.right: timeText.left
                                            anchors.rightMargin: 8
                                            text: model.from || ""
                                            color: MColors.textPrimary
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: MTypography.sizeBody
                                            font.weight: model.unread ? MTypography.weightBold : MTypography.weightMedium
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            id: timeText
                                            anchors.right: parent.right
                                            anchors.verticalCenter: fromText.verticalCenter
                                            text: model.timestamp || ""
                                            color: MColors.textSecondary
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: MTypography.sizeEyebrow
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        text: model.subject || ""
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        font.weight: model.unread ? MTypography.weightDemiBold : MTypography.weightRegular
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: model.snippet || ""
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeCaption
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (model.messageId) {
                                        emailApp.mail.markAsRead(model.messageId, true);
                                        inboxPage.messageOpenRequested(String(model.messageId));
                                    }
                                }
                            }
                        }
                    }
                }

                // Sync error overlay.
                Rectangle {
                    visible: emailApp.serviceAvailable && emailApp.mail.syncState === "error"
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: MSpacing.md
                    height: errorText.implicitHeight + 24
                    radius: MRadius.md
                    color: MColors.bb10Elevated
                    border.width: 1
                    border.color: Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.3)
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "x"
                            size: 16
                            color: MColors.error
                        }
                        Text {
                            id: errorText
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28
                            text: emailApp.mail.lastError || "Sync error"
                            color: MColors.error
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // Push the message viewer when a row asks for it.
            onMessageOpenRequested: mid => {
                navigationStack.push(messageComponent, {
                    "messageId": mid
                });
            }
        }
    }

    // ── Message viewer page ────────────────────────────────────────
    Component {
        id: messageComponent

        MailMessagePage {
            onBack: navigationStack.pop()
            onReplyRequested: prefill => {
                navigationStack.push(composeComponent, prefill || {});
            }
        }
    }

    // ── Compose page ───────────────────────────────────────────────
    Component {
        id: composeComponent

        MailComposePage {
            onBack: navigationStack.pop()
            onSent: navigationStack.pop()
        }
    }

    // ── IMAP account setup ─────────────────────────────────────────
    Component {
        id: setupComponent

        MailAccountSetupPage {
            onBack: navigationStack.pop()
            // accountCreated → pop back to inbox; the inbox auto-rebinds
            // via MailService.currentAccountChanged.
            onAccountCreated: navigationStack.pop()
        }
    }
}
