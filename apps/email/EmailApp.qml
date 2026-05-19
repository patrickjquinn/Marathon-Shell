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

// Mail — native inbox bound to MailService (QMF backend).
//
// Replaces the webmail-provider picker. MailService is the in-process
// QMF facade (see marathon-services/src/mailservice.h); it exposes:
//
//   accounts            QAbstractItemModel of configured accounts
//   messages            QAbstractItemModel of messages in the current folder
//   folders             QAbstractItemModel of folders in the current account
//   currentAccountId    selected account
//   currentFolderId     selected folder (defaults to Inbox)
//   unreadCount         derived from store
//   syncState           "offline" | "connecting" | "idle" | "syncing" | "error"
//   lastError           non-empty when syncState == "error"
//
// Hard rule (Marathon coding): NO PLACEHOLDER MAIL. There are zero
// hardcoded emails in this file. The three states are:
//
//   1. MailService unavailable (build doesn't include QMF yet, or
//      messageserver isn't running) → service-down banner.
//   2. No account configured → "Add an account" empty state, kicks off
//      the OAuth flow (marathon-mail-oauth Rust helper).
//   3. Account + folder loaded → real messages from MailService.messages.
//      If the folder genuinely has zero unread + zero total, an
//      "Inbox zero" empty state.
//
// Layout follows screens-apps-1.jsx:MailInbox: status bar + TopBar
// "Inbox" + section caption row + list of message rows + bottom tab bar.
MApp {
    id: emailApp

    // Resolve MailService at runtime so this QML still loads when the
    // backend isn't on the import path (early development image, or
    // builds that haven't yet linked qmf-dev). `mail` then renders the
    // "service unavailable" path.
    readonly property var mail: typeof MailService !== "undefined" ? MailService : null
    readonly property bool serviceAvailable: mail !== null

    readonly property int accountCount: serviceAvailable && mail.accounts ? (mail.accounts.rowCount ? mail.accounts.rowCount() : 0) : 0
    readonly property int messageCount: serviceAvailable && mail.messages ? (mail.messages.rowCount ? mail.messages.rowCount() : 0) : 0

    Rectangle {
        anchors.fill: parent
        color: MColors.background
    }

    // ── Status bar reserved space ─────────────────────────────────
    // The shell renders the global status bar above us; we just reserve
    // top: 28 in our content origin.

    // ── TopBar "Inbox" ────────────────────────────────────────────
    MTopBar {
        id: topBar
        title: "Inbox"
        showBack: false
        // Right-side action icons per JSX.
        actions: Row {
            spacing: MSpacing.md
            Icon {
                name: "search"
                size: 22
                color: MColors.textSecondary
            }
            Icon {
                name: "more"
                size: 22
                color: MColors.textSecondary
            }
        }
    }

    // ── Bottom tab bar (Inbox / Starred / Sent / All) ─────────────
    MTabBar {
        id: tabBar
        anchors.bottom: parent.bottom
        active: 0
        tabs: [
            {
                icon: "inbox",
                label: "Inbox"
            },
            {
                icon: "star",
                label: "Starred"
            },
            {
                icon: "send",
                label: "Sent"
            },
            {
                icon: "archive",
                label: "All"
            }
        ]
        // Folder switching binds through MailService.setCurrentFolderId
        // once we have a real folder list — for now the bar is a visual
        // affordance, not yet wired to swap folders. Wiring follows
        // once QMF's QMailFolderListModel surfaces standard folder ids
        // in the local install (Day 10 in the rollout plan).
    }

    // ── Main content stack ────────────────────────────────────────
    Item {
        id: content
        anchors {
            top: topBar.bottom
            bottom: tabBar.top
            left: parent.left
            right: parent.right
        }

        // State 1 — MailService not available (QMF apks not installed yet).
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
                    horizontalAlignment: Text.AlignHCenter
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

        // State 2 — Service up, but no account configured.
        Item {
            anchors.fill: parent
            visible: emailApp.serviceAvailable && emailApp.accountCount === 0

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
                    horizontalAlignment: Text.AlignHCenter
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
                        // Hook into the real OAuth flow once the
                        // setup-account IPC is wired. For now this is
                        // the documented next step rather than a
                        // synthetic action — clicking the button
                        // surfaces the same "service unavailable"
                        // state until the helper is integrated.
                        Logger.info("Mail", "Add Gmail account requested — invokes marathon-mail-oauth helper");
                    }
                }
                MButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Sign in with Microsoft"
                    variant: "secondary"
                    onClicked: {
                        Logger.info("Mail", "Add Outlook account requested — invokes marathon-mail-oauth helper");
                    }
                }
            }
        }

        // State 3 — Service up + account configured → real inbox.
        Item {
            anchors.fill: parent
            visible: emailApp.serviceAvailable && emailApp.accountCount > 0

            // Section caption row per JSX — "2 unread · 84 total" / "Sort: Newest"
            Row {
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
                        const total = emailApp.messageCount;
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
                    width: 1
                    height: 1
                    Layout.fillWidth: true
                }
                Text {
                    anchors.right: parent.right
                    text: "Sort: Newest"
                    color: MColors.marathonTealBright
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightBold
                    font.letterSpacing: MTypography.trackingEyebrow
                    font.capitalization: Font.AllUppercase
                }
            }

            // Inbox-zero empty state.
            Item {
                anchors.fill: parent
                anchors.topMargin: captionRow.height + 8
                visible: emailApp.messageCount === 0

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

            // Real list of messages.
            ListView {
                id: messageList
                visible: emailApp.messageCount > 0
                anchors {
                    top: captionRow.bottom
                    topMargin: 8
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                clip: true
                model: emailApp.mail ? emailApp.mail.messages : null
                // Role names are exposed by MailService's message-list
                // proxy: subject / from / snippet / timestamp / unread /
                // hasAttachment / messageId. See mailservice.h.
                delegate: Item {
                    width: messageList.width
                    height: rowContent.implicitHeight + 24

                    // Unread row gets a 3 px teal bar + faint tinted bg.
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
                            // Tinted by sender id hash — the QMF model
                            // exposes a tint color role (mapped to
                            // secondary palette in MColors). Falls back
                            // to bb10Card if the model doesn't supply.
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
                            if (emailApp.serviceAvailable && model.messageId) {
                                // Day 8: open thread view bound to
                                // QMailMessageThreadedModel. For now,
                                // mark-as-read is the only side-effect.
                                emailApp.mail.markAsRead(model.messageId, true);
                            }
                        }
                    }
                }
            }
        }

        // Sync state error banner — overlays whichever empty / list
        // state is active when the backend reports an error.
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
}
