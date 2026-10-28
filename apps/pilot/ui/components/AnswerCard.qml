// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// A written answer: the words set to be read, the pages they came from as
// chips (tap one to open it), the questions worth asking next as chips
// (tap one to ask it), and a quiet line saying where the answer was made
// and how long it took. Tapped, that line opens "How Pilot answered":
// what Pilot looked at, searched and used, and what left the phone.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Glass {
    id: card

    property string text
    property var sources: []
    property var followups: []
    property string via: ""            // phone, cloud, web
    property int ms: 0
    // pilotd's steps: [{"kind", "text"}] (memory, screen, page, web, app,
    // cloud), listed as they happened.
    property var how: []
    property bool showHow: false
    signal ask(string question)

    function provenance() {
        var t = ms > 0 ? (ms < 1000 ? ms + " ms" : (ms / 1000).toLocaleString(Qt.locale(), "f", 1) + " s") : ""
        var where = via === "web" ? qsTr("Web search")
                  : via === "cloud" ? qsTr("Pilot cloud")
                  : via === "phone" ? qsTr("On this phone") : ""
        return [where, t].filter(function(s) { return s.length > 0 }).join(" · ")
    }

    // Paragraphs, and lines starting "- " as a list with real bullets.
    readonly property var lines: text.split("\n").map(function(l) { return l.trim() })
                                     .filter(function(l) { return l.length > 0 })
    Column {
        objectName: "answerText"
        width: parent.width
        spacing: Theme.paddingSmall
        // A long press offers the answer's menu (Copy), as Silica does
        // for an item.
        MouseArea {
            parent: card
            anchors.fill: parent
            z: -1
            onPressAndHold: {
                if (!card._menu)
                    card._menu = menuComponent.createObject(menuHolder) as ContextMenu
                card._menu.open(menuHolder)
            }
        }
        Repeater {
            model: card.lines
            delegate: Item {
                id: line
                required property string modelData
                readonly property bool bullet: /^[-•*] /.test(line.modelData)
                width: parent ? parent.width : 0
                height: words.height
                Rectangle {
                    visible: line.bullet
                    y: words.font.pixelSize * 0.55
                    width: Theme.paddingSmall
                    height: width
                    radius: width / 2
                    color: Theme.highlightColor
                }
                Label {
                    id: words
                    x: line.bullet ? Theme.paddingLarge : 0
                    width: parent.width - x
                    text: line.bullet ? line.modelData.substring(2) : line.modelData
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.pixelSize: line.bullet ? Theme.fontSizeSmall : Theme.fontSizeMedium
                    lineHeight: 1.1
                    color: Theme.highlightColor
                }
            }
        }
    }

    // Where the menu opens: under the words.
    Item {
        id: menuHolder
        width: parent.width
        height: childrenRect.height
    }
    property ContextMenu _menu: null
    Component {
        id: menuComponent
        ContextMenu {
            MenuItem {
                text: qsTr("Copy")
                onClicked: {
                    Clipboard.text = card.text
                    Notices.show(qsTr("Copied"), Notice.Short)
                }
            }
        }
    }

    Flow {
        visible: card.sources.length > 0
        width: parent.width
        spacing: Theme.paddingSmall
        Repeater {
            model: card.sources
            delegate: Chip {
                id: sourceChip
                required property var modelData
                secondary: true
                monogram: sourceChip.modelData.site.charAt(0)
                text: sourceChip.modelData.site
                onClicked: Pilot.openUrl(sourceChip.modelData.url)
            }
        }
    }

    // Where it was made, and, tapped, how.
    BackgroundItem {
        objectName: "howToggle"
        visible: provenanceLabel.text.length > 0 || card.how.length > 0
        width: parent.width
        height: Theme.itemSizeSmall
        enabled: card.how.length > 0
        highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
        onClicked: {
            card.showHow = !card.showHow
            Conversation.markGuide("how")
        }
        Label {
            id: provenanceLabel
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (howLabel.visible ? howLabel.width + Theme.paddingMedium : 0)
            truncationMode: TruncationMode.Fade
            text: card.provenance()
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
        }
        Label {
            id: howLabel
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: card.how.length > 0
            text: card.showHow ? qsTr("Hide how") : qsTr("How Pilot answered")
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.highlightColor
        }
    }
    Column {
        objectName: "howSteps"
        visible: card.showHow
        width: parent.width
        spacing: Theme.paddingSmall
        Repeater {
            model: card.how
            delegate: Item {
                id: step
                required property var modelData
                width: parent ? parent.width : 0
                height: stepText.height
                Rectangle {
                    y: stepText.font.pixelSize * 0.55
                    width: Theme.paddingSmall
                    height: width
                    radius: width / 2
                    color: Theme.highlightColor
                }
                Label {
                    id: stepText
                    x: Theme.paddingLarge
                    width: parent.width - x
                    text: step.modelData.text
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                }
            }
        }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("Everything that left the phone is listed in Settings, under \u201cWhat left this phone\u201d.")
        }
    }

    // The next questions: full-width rows, one tap each.
    Column {
        visible: card.followups.length > 0
        width: parent.width
        topPadding: Theme.paddingSmall
        Repeater {
            model: card.followups
            delegate: BackgroundItem {
                id: followup
                required property string modelData
                width: parent ? parent.width : 0
                height: Math.max(Theme.itemSizeSmall, question.height + 2 * Theme.paddingMedium)
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, 0.25)
                onClicked: card.ask(followup.modelData)
                Separator {
                    width: parent.width
                    color: Theme.primaryColor
                }
                Label {
                    id: question
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - arrow.width - Theme.paddingMedium
                    text: followup.modelData
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: followup.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Icon {
                    id: arrow
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    source: "image://theme/icon-m-right"
                    color: Theme.highlightColor
                }
            }
        }
    }
}
