pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonOS.Services
import MarathonUI.Controls
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
// Layout follows the same DS chrome as MailMessagePage: MActionBar at
// top, header column for the recipient fields, wrap-text body. Send is
// an MButton in the action bar's right cluster, primary variant so it
// reads as the affirmative action.
Page {
    id: page

    // ── In ────────────────────────────────────────────────────────
    // Optional pre-fill for replies / "share to mail" flows.
    property string defaultTo: ""
    property string defaultCc: ""
    property string defaultSubject: ""
    property string defaultBody: ""

    // ── Out / signals ─────────────────────────────────────────────
    signal back
    signal sent

    // ── Derived ───────────────────────────────────────────────────
    readonly property var mail: typeof MailService !== "undefined" ? MailService : null
    readonly property bool serviceReady: mail !== null && mail.currentAccountId !== ""
    readonly property bool canSend: serviceReady && toField.text.trim() !== ""

    background: Rectangle {
        color: MColors.background
    }

    // ── Action bar — back + send ──────────────────────────────────
    MActionBar {
        id: actionBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        backLabel: "Cancel"
        onBackClicked: page.back()

        // Right-side primary action; per DS this lives in the trailing
        // cluster as a label-only chip, not a separate MButton — the bar
        // already enforces the DS press-spring + spacing.
        actions: [
            {
                icon: "send",
                label: "Send"
            }
        ]
        onActionSelected: index => {
            if (!page.canSend)
                return;
            const ok = page.mail.send(toField.text.trim(), ccField.text.trim(), subjectField.text, bodyArea.text,
            /* attachments */ []);
            if (ok) {
                page.sent();
                page.back();
            } else {
                errorBanner.message = "Send failed — see syncState / lastError.";
                errorBanner.visible = true;
            }
        }
    }

    // ── Service-unavailable banner ────────────────────────────────
    Rectangle {
        id: serviceBanner
        visible: !page.serviceReady
        anchors.top: actionBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        height: serviceBannerText.implicitHeight + 24
        radius: MRadius.md
        color: MColors.bb10Elevated
        border.width: 1
        border.color: MColors.borderDark
        Text {
            id: serviceBannerText
            anchors.fill: parent
            anchors.margins: 12
            text: page.mail === null ? "Mail backend is not running. Restart the device or check marathon-mailserver.service." : "No account configured. Add a Gmail or Outlook account from the inbox empty state first."
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
        property string message: ""
        visible: false
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        height: errorBannerText.implicitHeight + 24
        radius: MRadius.md
        color: MColors.bb10Elevated
        border.width: 1
        border.color: Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.3)

        Text {
            id: errorBannerText
            anchors.fill: parent
            anchors.margins: 12
            text: errorBanner.message
            color: MColors.error
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }
}
