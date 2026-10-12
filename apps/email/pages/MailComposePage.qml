pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Day 9 — compose sheet pushed onto the Mail stack from inbox "compose"
// action or message-view "reply" action.
//
// Wires the QML fields → MailService.send(to, cc, subject, body, attachments).
// MailService.send constructs a multipart QMailMessage, persists via
// QMailStore::addMessage, and kicks off QMailTransmitAction — which
// dispatches through QMF's SMTP plugin using XOAUTH2 credentials via
// our marathon-mail-oauth Rust helper (Day 4) / SASL plugin (Day 5).
//
// No-placeholder rules:
//   • Empty body / empty To stays empty — never inject a default.
//   • Send button is disabled until To is non-empty AND a current
//     account is configured. If MailService is unavailable we show
//     a service-down banner instead of letting the user type into
//     a void.
//   • Attachment list starts empty; attachments are picked via the
//     XDG-portal file picker (Day 10 wires the portal call).
//
// Layout: MTopBar with a primary Send button, header column for the
// recipient fields, wrap-text body. Leaving with edits saves a draft.
Page {
    id: page

    // ── In ────────────────────────────────────────────────────────
    // Optional pre-fill for replies / "share to mail" flows.
    property string defaultTo: ""
    property string defaultCc: ""
    property string defaultSubject: ""
    property string defaultBody: ""

    // FAB-opened compose restores the saved draft; replies start from their prefill.
    property bool restoreDraft: false

    // ── Out / signals ─────────────────────────────────────────────
    signal back
    signal sent
    signal draftSaved

    // ── Derived ───────────────────────────────────────────────────
    readonly property var mail: typeof MailService !== "undefined" ? MailService : null
    readonly property bool serviceReady: mail !== null && mail.currentAccountId !== ""
    readonly property bool canSend: serviceReady && toField.text.trim() !== ""
    readonly property string draftKey: "email/composeDraft"
    property var initialFields: ({})
    readonly property var fields: ({
            "to": toField.text,
            "cc": ccField.text,
            "subject": subjectField.text,
            "body": bodyArea.text
        })
    readonly property bool dirty: JSON.stringify(fields) !== JSON.stringify(initialFields)
    property string sendError: ""

    function persistDraft() {
        const empty = String(fields.to + fields.cc + fields.subject + fields.body).trim() === "";
        SettingsManagerCpp.set(draftKey, empty ? "" : JSON.stringify(fields));
        initialFields = fields;
        return !empty;
    }

    function send() {
        if (!canSend)
            return;
        sendError = "";
        if (mail.send(toField.text.trim(), ccField.text.trim(), subjectField.text, bodyArea.text, [])) {
            SettingsManagerCpp.set(draftKey, "");
            sent();
        } else {
            sendError = "Your message wasn't sent. Check the email address and your connection, then try again.";
        }
    }

    background: Rectangle {
        color: MColors.background
    }

    onBack: {
        autosave.stop();
        if (dirty && persistDraft())
            draftSaved();
    }
    onFieldsChanged: if (dirty)
        autosave.restart()
    Component.onCompleted: {
        const saved = restoreDraft ? SettingsManagerCpp.get(draftKey, "") : "";
        if (saved !== "") {
            const d = JSON.parse(saved);
            toField.text = d.to;
            ccField.text = d.cc;
            subjectField.text = d.subject;
            bodyArea.text = d.body;
        }
        initialFields = fields;
    }

    Timer {
        id: autosave
        interval: 2000
        onTriggered: page.persistDraft()
    }

    MTopBar {
        id: actionBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        title: page.defaultSubject !== "" ? "Reply" : "New message"
        showBack: true
        onBackClicked: page.back()

        actions: [
            MButton {
                text: "Send"
                variant: "primary"
                size: "compact"
                iconName: "paper-plane-right"
                disabled: !page.canSend
                onClicked: page.send()
            }
        ]
    }

    // ── Service-unavailable banner ────────────────────────────────
    Rectangle {
        id: serviceBanner
        visible: !page.serviceReady
        anchors.top: actionBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        height: serviceBannerText.implicitHeight + MSpacing.lg
        radius: MRadius.md
        color: MColors.bb10Elevated
        border.width: 1
        border.color: MColors.borderDark
        Text {
            id: serviceBannerText
            anchors.fill: parent
            anchors.margins: MSpacing.sm
            text: page.mail === null ? "Mail isn't available right now. Close Mail and open it again." : "Add a mail account before sending. Go back to the inbox to sign in."
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── Recipient fields ──────────────────────────────────────────
    Column {
        id: headerCol
        anchors.top: serviceBanner.visible ? serviceBanner.bottom : actionBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: MSpacing.md
        anchors.leftMargin: MSpacing.lg
        anchors.rightMargin: MSpacing.lg
        spacing: MSpacing.sm

        // From row — read-only display of current account's address.
        Row {
            width: parent.width
            spacing: MSpacing.sm
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "From"
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                width: 60
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60 - MSpacing.sm
                text: page.mail ? page.mail.currentAccountName || "—" : "—"
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.weight: MTypography.weightMedium
                elide: Text.ElideRight
            }
        }

        MTextField {
            id: toField
            label: "To"
            width: parent.width
            text: page.defaultTo
            placeholder: "email@example.com"
            enabled: page.serviceReady
        }

        MTextField {
            id: ccField
            label: "Cc"
            width: parent.width
            text: page.defaultCc
            placeholder: "(optional)"
            enabled: page.serviceReady
        }

        MTextField {
            id: subjectField
            label: "Subject"
            width: parent.width
            text: page.defaultSubject
            enabled: page.serviceReady
        }
    }

    // Divider between header + body.
    Rectangle {
        id: headerDivider
        anchors.top: headerCol.bottom
        anchors.topMargin: MSpacing.md
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: MColors.whiteOverlay04
    }

    // ── Body — wrap text input ────────────────────────────────────
    Flickable {
        anchors.top: headerDivider.bottom
        anchors.bottom: errorBanner.visible ? errorBanner.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        contentWidth: width
        contentHeight: bodyArea.implicitHeight + MSpacing.md
        clip: true

        TextArea {
            id: bodyArea
            width: parent.width
            text: page.defaultBody
            wrapMode: TextArea.Wrap
            enabled: page.serviceReady
            placeholderText: "Compose…"
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            background: null
        }
    }

    // ── Error banner (post-send failure) ──────────────────────────
    Rectangle {
        id: errorBanner
        visible: page.sendError !== ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        height: errorRow.implicitHeight + MSpacing.md
        radius: MRadius.md
        color: MColors.bb10Elevated
        border.width: 1
        border.color: MColors.errorDim

        Row {
            id: errorRow
            anchors.fill: parent
            anchors.leftMargin: MSpacing.md
            anchors.rightMargin: MSpacing.sm
            spacing: MSpacing.sm

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - retryButton.width - parent.spacing
                text: page.sendError
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                wrapMode: Text.WordWrap
            }
            MButton {
                id: retryButton
                anchors.verticalCenter: parent.verticalCenter
                text: "Retry"
                size: "compact"
                onClicked: page.send()
            }
        }
    }
}
