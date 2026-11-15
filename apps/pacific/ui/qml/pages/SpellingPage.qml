// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// The spell-checking dictionaries: the installed ones, each with a switch.
// With none chosen, the engine uses the phone's language.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "spellingPage"

    readonly property var s: JSON.parse(Pacific.settings)
    // What is checked now: the chosen dictionaries, else the engine's.
    readonly property var chosen: s.spell_languages && s.spell_languages.length > 0
                                  ? s.spell_languages : WebEngine.spellCheckingLanguages
    readonly property var available: {
        var list = WebEngine.availableSpellCheckingLanguages.slice()
        list.sort(function(a, b) { return Logic.languageName(a).localeCompare(Logic.languageName(b)) })
        return list
    }

    allowedOrientations: Orientation.All

    function toggle(code: var, on: var): var {
        var next = []
        for (var i = 0; i < chosen.length; ++i)
            if (chosen[i] !== code)
                next.push(chosen[i])
        if (on)
            next.push(code)
        if (next.length === 0)
            return false // at least one dictionary stays on
        Pacific.setSettings(JSON.stringify({ spell_languages: next }))
        return true
    }

    SilicaListView {
        anchors.fill: parent
        model: page.available

        header: Column {
            width: parent.width
            PageHeader { title: qsTr("Spelling languages") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Words are checked against every language chosen here.")
            }
        }

        delegate: TextSwitch {
            id: item
            required property string modelData
            objectName: "spell_" + item.modelData
            text: Logic.languageName(item.modelData)
            description: item.modelData.replace("_", "-")
            automaticCheck: false
            checked: page.chosen.indexOf(item.modelData) >= 0
            onClicked: page.toggle(item.modelData, !checked)
        }

        ViewPlaceholder {
            enabled: page.available.length === 0
            text: qsTr("No dictionaries installed")
        }

        VerticalScrollDecorator {}
    }
}
