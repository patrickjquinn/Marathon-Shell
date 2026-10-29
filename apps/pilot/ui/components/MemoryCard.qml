// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// What Pilot remembers: a fact just kept (with Undo), the list of what is
// kept (each with a way to forget it), or one just forgotten. All of it
// stays on the phone.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Glass {
    id: card

    property string text
    property string action: "remembered"     // remembered, forgotten, list, none
    property var facts: []
    // Facts forgotten from this card.
    property var gone: ({})

    function forget(id) {
        if (Pilot.forget(id)) {
            var g = Object.assign({}, gone);
            g[id] = true;
            gone = g;
        }
    }

    Row {
        spacing: Theme.paddingMedium
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmallPlus
            height: width
            source: "image://theme/icon-m-note"
            color: Theme.highlightColor
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: card.width - 2 * (Theme.horizontalPageMargin + card.padding) - Theme.iconSizeSmallPlus - Theme.paddingMedium
            text: card.text
            wrapMode: Text.Wrap
            color: Theme.highlightColor
        }
    }

    Repeater {
        model: card.facts
        delegate: Item {
            id: fact
            required property var modelData
            readonly property bool forgotten: card.action === "forgotten" || !!card.gone[fact.modelData.id]
            width: parent ? parent.width : 0
            height: Math.max(words.height, undo.visible ? undo.height : 0)
            Label {
                id: words
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (undo.visible ? undo.width + Theme.paddingMedium : 0)
                text: "“" + fact.modelData.fact + "”"
                wrapMode: Text.Wrap
                font.strikeout: fact.forgotten
                color: fact.forgotten ? Theme.secondaryColor : Theme.primaryColor
            }
            Chip {
                id: undo
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                visible: !fact.forgotten
                secondary: true
                text: card.action === "remembered" ? qsTr("Undo") : qsTr("Forget")
                onClicked: card.forget(fact.modelData.id)
            }
        }
    }

    Label {
        visible: card.action === "remembered" || card.action === "list"
        width: parent.width
        wrapMode: Text.Wrap
        text: qsTr("Kept on this phone. Say “forget …” or manage it in Settings.")
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
    }
}
