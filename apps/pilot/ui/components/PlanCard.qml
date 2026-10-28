// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot asking before it acts: what it will do, one numbered row per step
// (the app, the action, with what), the steps that need the person's yes
// marked, a plain note when something leaves the phone, and Allow or
// Cancel. Answered, it says which, and the buttons go.

import QtQuick
import Sailfish.Silica 1.0

Glass {
    id: card

    property string title
    property string detail
    property var steps: []
    property bool outbound: false
    property bool destructive: false
    property bool answered: false
    property bool approved: false
    signal answer(bool approved)

    accent: !answered

    Row {
        spacing: Theme.paddingMedium
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmallPlus
            height: width
            source: card.outbound ? "image://theme/icon-m-website" : "image://theme/icon-m-right"
            color: Theme.highlightColor
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: card.answered ? (card.approved ? qsTr("Done") : qsTr("Cancelled"))
                  : card.steps.length > 1 ? qsTr("Pilot will do this") : qsTr("Pilot wants to")
            color: Theme.highlightColor
        }
    }

    Repeater {
        model: card.steps.length > 0 ? card.steps : [{ title: card.title, app: "", detail: card.detail, needs_yes: true }]
        delegate: Row {
            id: step
            required property var modelData
            required property int index
            width: parent ? parent.width : 0
            spacing: Theme.paddingMedium
            Rectangle {
                width: Theme.iconSizeSmall
                height: width
                radius: width / 2
                color: step.modelData.needs_yes ? Theme.rgba(Theme.highlightColor, 0.35)
                                                : Theme.rgba(Theme.primaryColor, 0.12)
                Label {
                    anchors.centerIn: parent
                    text: step.index + 1
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.highlightColor
                }
            }
            Column {
                width: parent.width - Theme.iconSizeSmall - Theme.paddingMedium
                Label {
                    width: parent.width
                    text: step.modelData.app ? step.modelData.app + " · " + step.modelData.title : step.modelData.title
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                }
                Label {
                    width: parent.width
                    visible: text.length > 0
                    text: step.modelData.detail || ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                }
            }
        }
    }

    Label {
        visible: card.outbound && !card.answered
        width: parent.width
        wrapMode: Text.Wrap
        text: card.destructive ? qsTr("This leaves your phone and can't be undone.") : qsTr("This leaves your phone.")
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
    }

    Row {
        visible: !card.answered
        spacing: Theme.paddingMedium
        topPadding: Theme.paddingSmall
        Button {
            objectName: "allowButton"
            preferredWidth: Theme.buttonWidthExtraSmall
            text: qsTr("Allow")
            highlighted: true
            onClicked: card.answer(true)
        }
        Button {
            objectName: "cancelButton"
            preferredWidth: Theme.buttonWidthExtraSmall
            text: qsTr("Cancel")
            onClicked: card.answer(false)
        }
    }
}
