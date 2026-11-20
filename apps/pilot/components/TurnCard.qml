// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One entry of the conversation: the user's words, or one card from
// pilotd (response, clarify, confirm, camera, offline, error). Laid out as
// Jolla Messages lays out a conversation: what you said on the right, what
// Pilot said on the left, each inside the page margin on its own side and
// leaving the other side free, the time below the text. A confirmation
// card says what will happen and waits for Allow or Cancel; it is answered
// once and then says which. A camera card offers the viewfinder; its
// question travels in `detail`.

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Item {
    id: card

    required property string who      // "you" or "pilot"
    required property string kind
    required property string text
    required property string title
    required property string detail
    required property string cardId
    required property bool outbound
    required property bool destructive
    required property bool answered
    // A failed turn's code (pilotd's ErrorCode): what it says and offers.
    required property string code
    // When it was said (formatted by the page) and, for an answered
    // confirmation, whether it was allowed.
    property string stamp: ""
    property bool approved: false
    signal answer(bool approved)
    signal look(string question)
    signal openSettings
    signal retry
    signal download
    readonly property bool failed: !mine && (kind === "offline" || kind === "error")
    readonly property bool pointsToSettings: failed && code === "consent-needed"
    readonly property bool offersRetry: failed && !answered && ["offline", "model-loading", "timeout", "internal", ""].indexOf(code) >= 0
    readonly property bool offersDownload: failed && code === "model-unavailable"

    function headline() {
        switch (code) {
        case "offline":
            return qsTr("You're offline");
        case "model-unavailable":
            return qsTr("Pilot's model isn't on this phone yet");
        case "model-loading":
            return qsTr("Pilot is getting ready");
        case "timeout":
            return qsTr("That took too long");
        case "consent-needed":
            return qsTr("Pilot needs your permission");
        case "voice-unavailable":
            return qsTr("Speaking isn't available on this phone");
        default:
            return qsTr("Something went wrong");
        }
    }

    width: parent ? parent.width : 0
    height: bubble.height + Theme.paddingMedium

    readonly property bool mine: who === "you"

    Item {
        id: bubble
        objectName: "bubble"

        // The opposite side always keeps a free strip, as in Messages.
        readonly property real maximumWidth: Math.min(card.width - 2 * Theme.horizontalPageMargin - Theme.paddingLarge, 6 * Theme.itemSizeLarge)
        readonly property real naturalWidth: Math.max(titleLabel.visible ? titleLabel.implicitWidth : 0, textWidth.advanceWidth, stampLabel.implicitWidth, cameraButton.visible ? cameraButton.implicitWidth : 0, card.pointsToSettings || card.offersRetry || card.offersDownload ? Theme.buttonWidthSmall : 0, buttonRow.visible ? 2 * Theme.buttonWidthExtraSmall + Theme.paddingMedium : 0)
        width: Math.min(maximumWidth, naturalWidth)

        // The text's unwrapped width (a wrapping label's own implicit width
        // follows the width it is given).
        TextMetrics {
            id: textWidth
            font: textLabel.font
            text: textLabel.text
        }

        x: card.mine ? card.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
        height: content.height + 2 * Theme.paddingMedium

        Column {
            id: content
            y: Theme.paddingMedium
            width: bubble.width
            spacing: Theme.paddingSmall

            Label {
                id: titleLabel
                objectName: "cardTitle"
                visible: card.kind === "confirm" || card.failed
                width: parent.width
                wrapMode: card.failed ? Text.Wrap : Text.NoWrap
                truncationMode: TruncationMode.Fade
                color: Theme.primaryColor
                text: card.failed ? card.headline() : card.title
            }
            Label {
                id: textLabel
                objectName: "cardText"
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                horizontalAlignment: card.mine ? Text.AlignRight : Text.AlignLeft
                font.pixelSize: card.failed ? Theme.fontSizeSmall : Theme.fontSizeMedium
                color: card.failed ? Theme.secondaryColor : Theme.primaryColor
                text: card.kind === "confirm" ? card.detail : card.text
            }
            Label {
                objectName: "outboundNote"
                visible: card.kind === "confirm" && card.outbound
                width: parent.width
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("This leaves the phone")
            }
            Button {
                objectName: "settingsButton"
                visible: card.pointsToSettings
                preferredWidth: Theme.buttonWidthSmall
                text: qsTr("Open settings")
                onClicked: card.openSettings()
            }
            Button {
                objectName: "retryButton"
                visible: card.offersRetry
                preferredWidth: Theme.buttonWidthSmall
                text: qsTr("Try again")
                onClicked: card.retry()
            }
            Button {
                objectName: "downloadButton"
                visible: card.offersDownload
                preferredWidth: Theme.buttonWidthSmall
                text: qsTr("Download model")
                onClicked: card.download()
            }
            Button {
                id: cameraButton
                objectName: "cameraButton"
                visible: card.kind === "camera" && !card.answered
                preferredWidth: Theme.buttonWidthSmall
                text: qsTr("Take photo")
                onClicked: card.look(card.detail)
            }
            Row {
                id: buttonRow
                visible: card.kind === "confirm" && !card.answered
                width: parent.width
                spacing: Theme.paddingMedium
                Button {
                    objectName: "cancelButton"
                    width: (buttonRow.width - buttonRow.spacing) / 2
                    text: qsTr("Cancel")
                    onClicked: card.answer(false)
                }
                Button {
                    objectName: "allowButton"
                    width: (buttonRow.width - buttonRow.spacing) / 2
                    text: card.destructive ? qsTr("Do it") : qsTr("Allow")
                    onClicked: card.answer(true)
                }
            }
            Label {
                id: stampLabel
                objectName: "cardStamp"
                width: parent.width
                horizontalAlignment: card.mine ? Text.AlignRight : Text.AlignLeft
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                visible: text.length > 0
                text: card.kind === "confirm" && card.answered ? (card.approved ? qsTr("Allowed") : qsTr("Cancelled")) + (card.stamp.length > 0 ? " · " + card.stamp : "") : card.stamp
            }
        }
    }
}
