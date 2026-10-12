pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls // qmllint disable unused-imports
// ^ required at runtime for the StackView attached property (root.StackView.view);
//   qmllint does not count attached-property use, so it reports it unused.
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

    // Archive/Trash are deferred until the Undo snackbar expires.
    property string pendingMoveId: ""
    property string pendingMoveKind: ""

    function commitPendingMove() {
        if (pendingMoveId === "")
            return;
        const id = pendingMoveId;
        const kind = pendingMoveKind;
        pendingMoveId = "";
        pendingMoveKind = "";
        const ok = kind === "archive" ? mail.moveToArchive(id) : mail.moveToTrash(id);
        if (!ok)
            snackbar.show(kind === "archive" ? "No Archive folder on this account" : "Couldn't move to Trash. Try again.", "");
    }

    function notify(message, action) {
        commitPendingMove();
        snackbar.show(message, action);
    }

    function requestMove(messageId, kind) {
        notify(kind === "archive" ? "Message archived" : "Message moved to Trash", "Undo");
        pendingMoveId = messageId;
        pendingMoveKind = kind;
        navigationStack.pop();
    }

    function _back(page) {
        page.back();
    }

    navigationDepth: navigationStack.depth - 1

    onBackPressed: _back(navigationStack.currentItem)
    Component.onDestruction: commitPendingMove()

    Rectangle {
        anchors.fill: parent
        color: MColors.background
    }

    MStackView {
        id: navigationStack
        anchors.fill: parent
        initialItem: inboxComponent
    }

    MSnackbar {
        id: snackbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.md
        onActionTriggered: {
            emailApp.pendingMoveId = "";
            emailApp.pendingMoveKind = "";
        }
        onExpired: emailApp.commitPendingMove()
    }

    // ── Inbox page ─────────────────────────────────────────────────
    Component {
        id: inboxComponent

        Item {
            id: inboxPage

            signal messageOpenRequested(string messageId)

            // rowCount() is not notifiable; reading currentAccountId re-evaluates
            // this on currentAccountChanged, which fires on account add/remove.
            readonly property bool hasAccount: emailApp.serviceAvailable && emailApp.mail.currentAccountId !== "" && emailApp.mail.accounts.rowCount() > 0
            readonly property int messageCount: messageList.count
            readonly property string syncState: emailApp.serviceAvailable ? emailApp.mail.syncState : ""
            readonly property bool loading: messageCount === 0 && syncState !== "idle" && syncState !== "error"

            onHasAccountChanged: if (hasAccount)
                emailApp.mail.refresh()
            Component.onCompleted: if (hasAccount)
                emailApp.mail.refresh()

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
                    // Never relay `message` verbatim. The helper reports
                    // developer diagnostics — the keyring failure arrives as
                    // "MARATHON_PERM_SECRET_SERVICE not granted — app manifest
                    // must declare \"secret-service\" permission", which named
                    // an env var and a manifest key on a sign-in screen and
                    // gave the user nothing they could act on. Map to copy a
                    // person can use; keep the raw text in the log.
                    Logger.warn("Mail", "OAuth login failed [" + code + "]: " + message);
                    if (code === "oauth_not_configured")
                        inboxPage.oauthMessage = "OAuth sign-in isn't enabled in this build. Use Sign in with IMAP instead.";
                    else if (code === "secret_service_unavailable" || /secret[-_ ]service|keyring/i.test(message))
                        inboxPage.oauthMessage = "Marathon can't reach the keyring, so it can't store your account securely. Sign in with IMAP instead.";
                    else if (/network|timeout|resolve|connect/i.test(message))
                        inboxPage.oauthMessage = "Couldn't reach the sign-in service. Check your connection and try again.";
                    else
                        inboxPage.oauthMessage = "Sign-in didn't complete. Please try again.";
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
                            text: "Mail isn't available"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeHeadline
                            font.weight: MTypography.weightDemiBold
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: "Mail couldn't open your mailbox. Close Mail and open it again. If that doesn't help, restart your phone."
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
                    visible: emailApp.serviceAvailable && !inboxPage.hasAccount

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
                            text: "Sign in with Google or Microsoft, or use IMAP for any other provider."
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        MButton {
                            Layout.alignment: Qt.AlignHCenter
                            // Shared column width. MButton hugs its
                            // label, so a stacked group rendered at
                            // 352/388/424 px — visibly ragged.
                            Layout.fillWidth: true
                            Layout.maximumWidth: Math.round(320 * Constants.scaleFactor)
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
                            // Shared column width. MButton hugs its
                            // label, so a stacked group rendered at
                            // 352/388/424 px — visibly ragged.
                            Layout.fillWidth: true
                            Layout.maximumWidth: Math.round(320 * Constants.scaleFactor)
                            text: "Sign in with Microsoft"
                            variant: "secondary"
                            onClicked: {
                                if (emailApp.mail)
                                    emailApp.mail.startOAuthLogin("outlook");
                            }
                        }
                        MButton {
                            Layout.alignment: Qt.AlignHCenter
                            // Shared column width. MButton hugs its
                            // label, so a stacked group rendered at
                            // 352/388/424 px — visibly ragged.
                            Layout.fillWidth: true
                            Layout.maximumWidth: Math.round(320 * Constants.scaleFactor)
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
                    visible: inboxPage.hasAccount

                    Text {
                        id: captionText
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            topMargin: MSpacing.sm
                            leftMargin: MSpacing.lg
                            rightMargin: MSpacing.lg
                        }
                        text: {
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

                    Rectangle {
                        id: syncErrorBanner
                        visible: inboxPage.syncState === "error" && inboxPage.messageCount > 0
                        anchors.top: captionText.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: MSpacing.md
                        height: visible ? bannerRow.implicitHeight + MSpacing.md : 0
                        radius: MRadius.md
                        color: MColors.bb10Elevated
                        border.width: 1
                        border.color: MColors.errorDim

                        RowLayout {
                            id: bannerRow
                            anchors.fill: parent
                            anchors.leftMargin: MSpacing.md
                            anchors.rightMargin: MSpacing.sm
                            spacing: MSpacing.sm

                            Text {
                                Layout.fillWidth: true
                                text: "Couldn't check for new mail. Check your connection and try again."
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                wrapMode: Text.WordWrap
                            }
                            MButton {
                                text: "Retry"
                                size: "compact"
                                onClicked: emailApp.mail.refresh()
                            }
                        }
                    }

                    Item {
                        id: listArea
                        anchors {
                            top: syncErrorBanner.visible ? syncErrorBanner.bottom : captionText.bottom
                            topMargin: MSpacing.sm
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: inboxPage.loading
                            spacing: MSpacing.md
                            MActivityIndicator {
                                Layout.alignment: Qt.AlignHCenter
                                running: parent.visible
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Checking for mail…"
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: inboxPage.messageCount === 0 && inboxPage.syncState === "idle"
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
                                text: "All caught up."
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - MSpacing.xl * 2
                            visible: inboxPage.messageCount === 0 && inboxPage.syncState === "error"
                            spacing: MSpacing.md
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Couldn't load your mail"
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeHeadline
                                font.weight: MTypography.weightDemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Check your connection, then try again. If it keeps failing, your provider may need you to sign in again."
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                            MButton {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Retry"
                                variant: "primary"
                                onClicked: emailApp.mail.refresh()
                            }
                        }

                        ListView {
                            id: messageList
                            anchors.fill: parent
                            visible: inboxPage.messageCount > 0
                            clip: true
                            bottomMargin: composeFab.height + MSpacing.lg * 2
                            model: emailApp.mail ? emailApp.mail.messages : null
                            delegate: Item {
                                id: messageRow
                                required property var model
                                readonly property bool pendingMove: String(model.messageId) === emailApp.pendingMoveId

                                function open() {
                                    if (model.messageId) {
                                        emailApp.mail.markAsRead(model.messageId, true);
                                        inboxPage.messageOpenRequested(String(model.messageId));
                                    }
                                }

                                width: messageList.width
                                height: pendingMove ? 0 : rowContent.implicitHeight + 24
                                visible: !pendingMove

                                Accessible.role: Accessible.Button
                                Accessible.name: (model.unread ? "Unread. " : "") + (model.from || "") + ", " + (model.subject || "")
                                Accessible.onPressAction: open()

                                Rectangle {
                                    anchors.fill: parent
                                    color: messageRow.model.unread ? MColors.tealTintDark : "transparent"
                                }
                                Rectangle {
                                    visible: messageRow.model.unread
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
                                        color: messageRow.model.tint || MColors.bb10Card
                                        border.width: 1
                                        border.color: MColors.whiteOverlay08
                                        Text {
                                            anchors.centerIn: parent
                                            text: (messageRow.model.from || "?").substring(0, 1).toUpperCase()
                                            color: MColors.textPrimary
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
                                                text: messageRow.model.from || ""
                                                color: MColors.textPrimary
                                                font.family: MTypography.fontFamily
                                                font.pixelSize: MTypography.sizeBody
                                                font.weight: messageRow.model.unread ? MTypography.weightBold : MTypography.weightMedium
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                id: timeText
                                                anchors.right: parent.right
                                                anchors.verticalCenter: fromText.verticalCenter
                                                text: messageRow.model.timestamp || ""
                                                color: MColors.textSecondary
                                                font.family: MTypography.fontFamily
                                                font.pixelSize: MTypography.sizeEyebrow
                                            }
                                        }
                                        Text {
                                            width: parent.width
                                            text: messageRow.model.subject || ""
                                            color: MColors.textPrimary
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: MTypography.sizeFootnote
                                            font.weight: messageRow.model.unread ? MTypography.weightDemiBold : MTypography.weightRegular
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: messageRow.model.snippet || ""
                                            color: MColors.textSecondary
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: MTypography.sizeCaption
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: messageRow.open()
                                }
                            }
                        }
                    }

                    MFloatingActionButton {
                        id: composeFab
                        label: "New message"
                        iconName: "pencil-simple"
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: MSpacing.lg
                        anchors.bottomMargin: MSpacing.lg + (snackbar.open ? snackbar.height + MSpacing.md : 0)
                        onClicked: navigationStack.push(composeComponent, {
                            "restoreDraft": true
                        })
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
            id: messagePage
            onBack: navigationStack.pop()
            onMoveRequested: kind => emailApp.requestMove(messagePage.messageId, kind)
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
            onDraftSaved: emailApp.notify("Draft saved", "")
            onSent: {
                navigationStack.pop();
                emailApp.notify("Sending message…", "");
            }
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
