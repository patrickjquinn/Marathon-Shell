// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One entry of the conversation: the user's words, or one card from
// pilotd (response, clarify, confirm, camera, offline, error). Laid out as
// Jolla Messages lays out a conversation: what you said on the right, what
// Pilot said on the left, each bubble attached to its own screen edge and
// leaving the other side free, the time below the text. A confirmation
// card says what will happen and waits for Allow or Cancel; it is answered
// once and then says which. A camera card offers the viewfinder; its
// question travels in `detail`.

import QtQuick
import Sailfish.Silica 1.0

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
    // When it was said (formatted by the page) and, for an answered
    // confirmation, whether it was allowed.
    property string stamp: ""
    property bool approved: false
    signal answer(bool approved)
    signal look(string question)
    signal openSettings()
    // A reply that points to a setting (spoken or typed questions are
    // off) takes you there.
    readonly property bool pointsToSettings: !mine && (kind === "offline" || kind === "error")
                                             && text.indexOf("Pilot's settings") >= 0

    width: parent ? parent.width : 0
    height: bubble.height + Theme.paddingMedium

    readonly property bool mine: who === "you"
    readonly property bool pending: (kind === "confirm" || kind === "camera") && !answered

    // The bubble. Its corners on the screen-edge side are outside the page
    // (the list clips them), so it reads as attached to that edge.
    Rectangle {
        id: bubble
        objectName: "bubble"

        // The opposite side always keeps a free strip, as in Messages.
        readonly property real maximumWidth: Math.min(card.width - Theme.horizontalPageMargin - Theme.paddingLarge,
                                                      6 * Theme.itemSizeLarge)
        readonly property real naturalWidth: Math.max(titleLabel.visible ? titleLabel.implicitWidth : 0,
                                                      textWidth.advanceWidth,
                                                      stampLabel.implicitWidth,
                                                      cameraButton.visible ? cameraButton.implicitWidth : 0,
                                                      card.pointsToSettings ? Theme.buttonWidthSmall : 0,
                                                      buttonRow.visible ? 2 * Theme.buttonWidthExtraSmall + Theme.paddingMedium : 0)
        width: Math.min(maximumWidth, naturalWidth + Theme.horizontalPageMargin + Theme.paddingLarge)

        // The text's unwrapped width (a wrapping label's own implicit width
        // follows the width it is given).
        TextMetrics {
            id: textWidth
            font: textLabel.font
            text: textLabel.text
        }

        x: card.mine ? card.width - width : 0
        height: content.height + 2 * Theme.paddingMedium

        // Drawn wider than `width` by its radius, past the screen edge.
        color: "transparent"
        Rectangle {
            x: card.mine ? 0 : -radius
            width: parent.width + radius
            height: parent.height
            radius: Theme.paddingLarge
            color: card.kind === "confirm" && card.pending
                   ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
                   : card.mine ? Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityFaint)
                   : Theme.rgba(Theme.primaryColor, 0.08)
        }

        Column {
            id: content
            // Text starts at the page margin on the edge side.
            x: card.mine ? Theme.paddingLarge : Theme.horizontalPageMargin
            y: Theme.paddingMedium
            width: bubble.width - Theme.horizontalPageMargin - Theme.paddingLarge
            spacing: Theme.paddingSmall

            Label {
                id: titleLabel
                objectName: "cardTitle"
                visible: card.kind === "confirm"
                width: parent.width
                truncationMode: TruncationMode.Fade
                color: Theme.highlightColor
                text: card.title
            }
            Label {
                id: textLabel
                objectName: "cardText"
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                horizontalAlignment: card.mine ? Text.AlignRight : Text.AlignLeft
                color: card.kind === "error" ? Theme.errorColor
                     : card.kind === "offline" ? Theme.highlightColor
                     : Theme.primaryColor
                text: card.kind === "confirm" ? card.detail : card.text
            }
            Label {
                objectName: "outboundNote"
                visible: card.kind === "confirm" && card.outbound
                width: parent.width
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
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
                color: card.mine ? Theme.secondaryHighlightColor : Theme.secondaryColor
                visible: text.length > 0
                text: card.kind === "confirm" && card.answered
                      ? (card.approved ? qsTr("Allowed") : qsTr("Cancelled"))
                        + (card.stamp.length > 0 ? " · " + card.stamp : "")
                      : card.stamp
            }
        }
    }
}
