// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pacific's settings: search, tabs, content, reader mode, passwords and
// Pilot here; privacy and security on their own page.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "settingsPage"

    property var browser
    readonly property var s: JSON.parse(Pacific.settings)
    readonly property var engines: JSON.parse(Pacific.engines)

    allowedOrientations: Orientation.All

    function set(key: var, value: var): void {
        var patch = {};
        patch[key] = value;
        Pacific.setSettings(JSON.stringify(patch));
    }

    function engineName(): var {
        for (var i = 0; i < engines.length; ++i)
            if (engines[i].id === Pacific.defaultEngine)
                return engines[i].name;
        return "";
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("About Pacific")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: qsTr("Privacy and security")
                onClicked: pageStack.push(Qt.resolvedUrl("PrivacyPage.qml"), {
                    browser: page.browser
                })
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            BackgroundItem {
                id: privacyEntry
                objectName: "privacyEntry"
                width: parent.width
                height: Theme.itemSizeMedium
                onClicked: pageStack.push(Qt.resolvedUrl("PrivacyPage.qml"), {
                    browser: page.browser
                })
                Icon {
                    id: privacyIcon
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-browser-permissions"
                    highlighted: privacyEntry.highlighted
                }
                Label {
                    anchors {
                        left: privacyIcon.right
                        leftMargin: Theme.paddingMedium
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    text: qsTr("Privacy and security")
                    color: privacyEntry.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }

            SectionHeader {
                text: qsTr("Search")
            }

            ValueButton {
                objectName: "engineButton"
                label: qsTr("Search engine")
                value: page.engineName()
                onClicked: pageStack.push(Qt.resolvedUrl("SearchEnginesPage.qml"))
            }
            TextSwitch {
                text: qsTr("Search suggestions")
                description: qsTr("What you type is sent to the search engine for suggestions. Not in private tabs or for addresses.")
                checked: page.s.search_suggestions
                onClicked: page.set("search_suggestions", checked)
            }

            SectionHeader {
                text: qsTr("Tabs")
            }

            ComboBox {
                label: qsTr("Restore tabs at start")
                currentIndex: ["always", "crash", "never"].indexOf(page.s.restore)
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Always")
                        onClicked: page.set("restore", "always")
                    }
                    MenuItem {
                        text: qsTr("After a crash")
                        onClicked: page.set("restore", "crash")
                    }
                    MenuItem {
                        text: qsTr("Never")
                        onClicked: page.set("restore", "never")
                    }
                }
            }
            TextSwitch {
                text: qsTr("Hide the toolbar while scrolling")
                checked: page.s.toolbar_autohide
                onClicked: page.set("toolbar_autohide", checked)
            }

            SectionHeader {
                text: qsTr("Pages")
            }

            TextSwitch {
                text: qsTr("JavaScript")
                description: qsTr("Most sites need it. To turn it off for one site, use that site's settings.")
                checked: page.s.javascript
                onClicked: page.set("javascript", checked)
            }
            TextSwitch {
                text: qsTr("Desktop sites")
                description: qsTr("Ask sites for their desktop version")
                checked: page.s.desktop_mode
                onClicked: page.set("desktop_mode", checked)
            }
            TextSwitch {
                text: qsTr("Play media without a tap")
                checked: page.s.autoplay
                onClicked: page.set("autoplay", checked)
            }
            Slider {
                width: parent.width
                label: qsTr("Page zoom")
                minimumValue: 50
                maximumValue: 200
                stepSize: 10
                value: Math.round(page.s.default_zoom * 100)
                valueText: Math.round(value) + "%"
                onReleased: page.set("default_zoom", value / 100)
            }

            SectionHeader {
                text: qsTr("Spelling")
            }

            TextSwitch {
                objectName: "spellSwitch"
                text: qsTr("Check spelling")
                description: qsTr("Underline misspelt words in text fields. Press and hold a word for suggestions.")
                checked: page.s.spell_check
                onClicked: page.set("spell_check", checked)
            }
            ValueButton {
                objectName: "spellLanguages"
                enabled: page.s.spell_check
                label: qsTr("Languages")
                value: {
                    var langs = page.s.spell_languages && page.s.spell_languages.length > 0 ? page.s.spell_languages : WebEngine.spellCheckingLanguages;
                    var names = [];
                    for (var i = 0; i < langs.length; ++i)
                        names.push(Logic.languageName(langs[i]));
                    return names.join(", ");
                }
                onClicked: pageStack.push(Qt.resolvedUrl("SpellingPage.qml"))
            }

            ComboBox {
                label: qsTr("Website colours")
                description: qsTr("Light or dark, for websites that offer both")
                currentIndex: ["ambience", "light", "dark"].indexOf(page.s.color_scheme)
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Follow the ambience")
                        onClicked: page.set("color_scheme", "ambience")
                    }
                    MenuItem {
                        text: qsTr("Light")
                        onClicked: page.set("color_scheme", "light")
                    }
                    MenuItem {
                        text: qsTr("Dark")
                        onClicked: page.set("color_scheme", "dark")
                    }
                }
            }

            SectionHeader {
                text: qsTr("Reader mode")
            }

            ComboBox {
                label: qsTr("Colours")
                currentIndex: ["light", "sepia", "dark"].indexOf(page.s.reader_theme)
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Light")
                        onClicked: page.set("reader_theme", "light")
                    }
                    MenuItem {
                        text: qsTr("Sepia")
                        onClicked: page.set("reader_theme", "sepia")
                    }
                    MenuItem {
                        text: qsTr("Dark")
                        onClicked: page.set("reader_theme", "dark")
                    }
                }
            }
            Slider {
                width: parent.width
                label: qsTr("Text size")
                minimumValue: 12
                maximumValue: 32
                stepSize: 1
                value: page.s.reader_font_px
                valueText: Math.round(value) + " px"
                onReleased: page.set("reader_font_px", Math.round(value))
            }
            TextSwitch {
                text: qsTr("Serif typeface")
                checked: page.s.reader_serif
                onClicked: page.set("reader_serif", checked)
            }

            SectionHeader {
                text: qsTr("Passwords")
            }

            TextSwitch {
                text: qsTr("Fill logins with Shoal Keys")
                description: qsTr("Offer to fill login forms from Shoal Keys. Pacific never stores passwords itself.")
                checked: page.s.keys_autofill
                onClicked: page.set("keys_autofill", checked)
            }

            SectionHeader {
                text: qsTr("Pilot")
            }

            TextSwitch {
                text: qsTr("Let Pilot use the browser")
                description: qsTr("Pilot can open pages, read them to you and browse in a private background tab. It asks before clicking, filling in or sending anything. It never fills in passwords or payment details.")
                checked: page.s.pilot_actions
                onClicked: page.set("pilot_actions", checked)
            }

            SectionHeader {
                text: qsTr("Default browser")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                text: qsTr("To open links from other apps in Pacific, choose it in Settings > Apps > Default apps.")
            }
        }
        VerticalScrollDecorator {}
    }
}
