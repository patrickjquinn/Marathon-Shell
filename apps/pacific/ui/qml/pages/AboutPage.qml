// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// About Pacific: version, engine, privacy promise and credits.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0

Page {
    id: page
    objectName: "aboutPage"

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("About Pacific") }

            DetailItem { label: qsTr("Version"); value: Pacific.version }
            DetailItem { label: qsTr("Web engine"); value: "WPE WebKit " + WebEngine.version }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: qsTr("Pacific is free, with no telemetry, ads or account. It only connects on its own to update its filter lists, and to your search engine for suggestions if you allow it.")
            }
            SectionHeader { text: qsTr("Thanks") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("WPE WebKit (LGPL and BSD licences). Atlantic Browser by SpecSierra, whose engine build and Qt view Pacific's are ported from (MPL-2.0, LGPL). Brave's adblock-rust (MPL-2.0). DuckDuckGo's autoconsent (MPL-2.0). EasyList, EasyPrivacy, uBlock Origin's filter lists and Peter Lowe's list. dom_smoothie, a Rust port of Mozilla's Readability (MIT).")
            }
        }
        VerticalScrollDecorator {}
    }
}
