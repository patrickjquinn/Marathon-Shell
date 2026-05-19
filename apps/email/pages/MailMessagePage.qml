pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

// Day 8 — single-message viewer pushed onto the Mail app stack when a
// user taps a row in EmailApp.qml's inbox list.
//
// Receives a messageId (the string-encoded QMailMessageId surfaced via
// the messages model's "messageId" role) and binds to whatever
// MailService.openMessage returns for that id.
//
// Hard rule (Marathon coding): NO PLACEHOLDER BODY. If MailService is
// unavailable, if openMessage returns an empty map, or if the body
// payload is empty, this page renders the empty state explicitly —
// it never invents a body.
//
// Body rendering: QtWebEngineView when the message has bodyHtml,
// monospace Text when it's plain. HTML rendering is intentionally
// scoped to the Mail app process (we drop the webengine requirement
// from the manifest earlier — but the app-runner still keeps it
// available when the app actually invokes it, lazy-loaded). External
// resource loading is OFF by default (privacy: no remote-image
// tracking pixels on inbox open).
Page {
    id: page

    // ── In ────────────────────────────────────────────────────────
    property string messageId: ""

    // ── Out / signals ─────────────────────────────────────────────
    signal back
    // Emitted when the user taps Reply. The pre-fill map seeds the
    // compose sheet (defaultTo, defaultSubject, defaultBody) so the
    // user lands in a draft that already quotes the original.
    signal replyRequested(var prefill)

    // ── Derived ───────────────────────────────────────────────────
    readonly property var mail: typeof MailService !== "undefined" ? MailService : null
    readonly property var msg: mail && messageId !== "" ? mail.openMessage(messageId) : ({})
    readonly property string subject: msg.subject || ""
    readonly property string fromAddr: msg.from || ""
    readonly property var toList: msg.to || []
    readonly property var ccList: msg.cc || []
    readonly property var date: msg.date || null
    readonly property string bodyHtml: msg.bodyHtml || ""
    readonly property string bodyPlain: msg.bodyPlain || ""
    readonly property var attachments: msg.attachments || []
    readonly property bool hasBody: bodyHtml.length > 0 || bodyPlain.length > 0

    background: Rectangle {
        color: MColors.background
    }

    // Action bar at top — back arrow, then per-message actions (archive,
    // trash, reply). Spec-tight: 8-px gap between icon and label per the
    // DS button spacing rule we already fixed.
    MActionBar {
        id: actionBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        backLabel: "Inbox"
        onBackClicked: page.back()

        actions: [
            {
                icon: "archive",
                label: "Archive"
            },
            {
                icon: "trash",
                label: "Trash"
            },
            {
                icon: "arrow-bend-up-left",
                label: "Reply"
            }
        ]
        onActionTriggered: index => {
            if (!page.mail)
                return;
            if (index === 0)
                page.mail.moveToArchive(page.messageId);
            else if (index === 1)
                page.mail.moveToTrash(page.messageId);
            else if (index === 2) {
                const subj = (page.subject || "").trim();
                const reSubj = /^re:/i.test(subj) ? subj : ("Re: " + subj);
                const quote = (page.bodyPlain || "").split("\n").map(l => "> " + l).join("\n");
                page.replyRequested({
                    "defaultTo": page.fromAddr || "",
                    "defaultSubject": reSubj,
                    "defaultBody": "\n\n" + quote
                });
            }
        }
    }

    // Header (subject + from + to + date) — DS Title 3 for subject,
    // Footnote for headers, Eyebrow for the date strip.
    Item {
        id: header
        anchors.top: actionBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: headerCol.implicitHeight + MSpacing.lg * 2

        Column {
            id: headerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: MSpacing.lg
            anchors.rightMargin: MSpacing.lg
            anchors.topMargin: MSpacing.lg
            spacing: MSpacing.xs

            Text {
                text: page.subject !== "" ? page.subject : "(no subject)"
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeTitle3
                font.weight: MTypography.weightMedium
                font.letterSpacing: MTypography.trackingTitle3
                width: parent.width
                wrapMode: Text.WordWrap
            }
            Text {
                text: "From " + page.fromAddr
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                visible: page.fromAddr !== ""
                width: parent.width
                elide: Text.ElideRight
            }
            Text {
                text: "To " + page.toList.join(", ")
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                visible: page.toList.length > 0
                width: parent.width
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                text: "Cc " + page.ccList.join(", ")
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                visible: page.ccList.length > 0
                width: parent.width
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                text: page.date ? Qt.formatDateTime(page.date, "d MMM yyyy, HH:mm") : ""
                color: MColors.textTertiary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightBold
                font.letterSpacing: MTypography.trackingEyebrow
                font.capitalization: Font.AllUppercase
                visible: page.date !== null
            }
        }
    }

    // Divider hairline between header and body — same white-04 the
    // inbox row dividers use.
    Rectangle {
        id: headerDivider
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: MColors.whiteOverlay04
    }

    // Body — three render paths:
    //   • bodyHtml non-empty → QtWebEngineView (offline, no remote loads)
    //   • bodyPlain non-empty → wrap-text rendering
    //   • neither → "(no body)" empty state
    Item {
        id: bodyArea
        anchors.top: headerDivider.bottom
        anchors.bottom: attachStrip.visible ? attachStrip.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md

        WebEngineView {
            id: htmlView
            anchors.fill: parent
            visible: page.bodyHtml.length > 0
            // Privacy: don't auto-load external resources. Users who
            // want images get an explicit toggle (Day 9 wires that).
            settings.autoLoadImages: false
            settings.javascriptEnabled: false
            settings.localContentCanAccessRemoteUrls: false
            settings.localContentCanAccessFileUrls: false
            Component.onCompleted: {
                if (page.bodyHtml.length > 0)
                    loadHtml(page.bodyHtml);
            }
            onLoadingChanged: function (info) {
                // Surface load failures via the Logger; clients won't
                // see them but the journald path captures for debug.
                if (info.status === WebEngineView.LoadFailedStatus)
                    Logger.warn("Mail", "Body HTML load failed: " + info.errorString);
            }
        }

        Flickable {
            anchors.fill: parent
            visible: page.bodyHtml.length === 0 && page.bodyPlain.length > 0
            contentWidth: width
            contentHeight: plainBody.implicitHeight + MSpacing.md
            clip: true
            Text {
                id: plainBody
                width: parent.width
                text: page.bodyPlain
                color: MColors.textPrimary
                font.family: MTypography.fontFamilyMono
                font.pixelSize: MTypography.sizeFootnote
                wrapMode: Text.Wrap
            }
        }

        // Empty body state — explicit, not silent.
        Item {
            anchors.fill: parent
            visible: !page.hasBody && page.mail !== null

            ColumnLayout {
                anchors.centerIn: parent
                spacing: MSpacing.xs
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "(no body)"
                    color: MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                }
            }
        }
    }

    // Attachment strip — pinned at the bottom when present. Renders the
    // attachment list from QMailMessage parts; opens via Marathon's
    // file portal (Day 10 wires the open-with action).
    Rectangle {
        id: attachStrip
        visible: page.attachments.length > 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        color: MColors.bb10Elevated
        border.width: 1
        border.color: MColors.borderDark

        MTopHairline {
            radius: 0
            color: MColors.whiteOverlay06
        }

        ListView {
            anchors.fill: parent
            anchors.leftMargin: MSpacing.md
            anchors.rightMargin: MSpacing.md
            orientation: ListView.Horizontal
            spacing: MSpacing.sm
            clip: true
            model: page.attachments
            delegate: Rectangle {
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                width: nameLabel.implicitWidth + 36
                height: 32
                radius: MRadius.md
                color: MColors.bb10Card
                border.width: 1
                border.color: MColors.whiteOverlay08
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "paperclip"
                        size: 14
                        color: MColors.textSecondary
                    }
                    Text {
                        id: nameLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name || "attachment"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: MTypography.weightMedium
                    }
                }
            }
        }
    }
}
