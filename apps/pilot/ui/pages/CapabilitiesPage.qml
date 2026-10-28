// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// What Pilot can do: what it does by itself on the phone, what it does
// with the web, and, read from pilotd (Capabilities), what it can do in
// each of the person's apps, with the actions that wait for their yes
// marked. A tap on something Pilot does by itself asks it.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Page {
    id: page
    objectName: "capabilitiesPage"

    // The apps' actions as a person reads them: without the lookups Pilot
    // uses between steps (an entity's find tool), and each described by
    // its first sentence (the rest is written for the model).
    readonly property var apps: JSON.parse(Pilot.capabilities() || "[]").map(function(app) {
        return {
            name: app.name,
            actions: app.actions.filter(function(a) {
                return a.description.indexOf("Returns references") < 0
            }).map(function(a) {
                var end = a.description.search(/[.!?](\s|$)/)
                var first = end >= 0 ? a.description.substring(0, end + 1) : a.description
                return { title: a.title, description: first, asks: a.asks }
            })
        }
    }).filter(function(app) { return app.actions.length > 0 })

    readonly property var builtIn: [
        { icon: "image://theme/icon-m-timer", title: qsTr("Timers, alarms and reminders"), ask: qsTr("Timer for 10 minutes") },
        { icon: "image://theme/icon-m-date", title: qsTr("Your calendar"), ask: qsTr("What's on today?") },
        { icon: "image://theme/icon-m-note", title: qsTr("Remembering things for you"), ask: qsTr("What do you remember about me?") },
        { icon: "image://theme/icon-m-device", title: qsTr("What's on screen, over any app"), ask: "" },
        { icon: "image://theme/icon-m-website", title: qsTr("Today's web, with its sources"), ask: qsTr("What's in the news?") },
        { icon: "image://theme/icon-m-search-on-page", title: qsTr("Photos you take"), ask: "" }
    ]

    // Back on the main page with a question.
    function ask(question) {
        var main = pageStack.find(function(p) { return p.objectName === "mainPage" })
        if (!main)
            return
        pageStack.pop(main)
        main.send(question)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("What Pilot can do")
            }

            SectionHeader { text: qsTr("By itself") }
            Repeater {
                model: page.builtIn
                delegate: BackgroundItem {
                    id: skill
                    required property var modelData
                    width: column.width
                    // As tall as its two lines need at a large text size.
                    height: Math.max(Theme.itemSizeMedium, skillText.height + 2 * Theme.paddingMedium)
                    enabled: skill.modelData.ask.length > 0
                    onClicked: page.ask(skill.modelData.ask)
                    Icon {
                        id: skillIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: skill.modelData.icon
                        color: Theme.highlightColor
                    }
                    Column {
                        id: skillText
                        anchors {
                            left: skillIcon.right; leftMargin: Theme.paddingLarge
                            right: parent.right; rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: skill.modelData.title
                            color: skill.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            visible: text.length > 0
                            truncationMode: TruncationMode.Fade
                            text: skill.modelData.ask.length > 0 ? qsTr("Try “%1”").arg(skill.modelData.ask) : ""
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: skill.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("In your apps") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                bottomPadding: Theme.paddingMedium
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.apps.length > 0
                      ? qsTr("Apps tell Pilot what they can do. Pilot asks before anything marked “asks first”.")
                      : qsTr("None of your apps offer Pilot actions yet.")
            }
            Repeater {
                model: page.apps
                delegate: Column {
                    id: app
                    required property var modelData
                    // The first few; all once asked for.
                    property bool all: modelData.actions.length <= 5
                    width: column.width
                    bottomPadding: Theme.paddingLarge
                    spacing: Theme.paddingSmall
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        text: app.modelData.name
                        font.pixelSize: Theme.fontSizeLarge
                        font.family: Theme.fontFamilyHeading
                        color: Theme.highlightColor
                    }
                    Repeater {
                        model: app.all ? app.modelData.actions : app.modelData.actions.slice(0, 4)
                        delegate: Column {
                            id: action
                            required property var modelData
                            x: Theme.horizontalPageMargin
                            width: app.width - 2 * x
                            Label {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: action.modelData.asks ? qsTr("%1 · asks first").arg(action.modelData.title)
                                                            : action.modelData.title
                                color: Theme.highlightColor
                            }
                            Label {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: action.modelData.description
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryHighlightColor
                            }
                        }
                    }
                    BackgroundItem {
                        visible: !app.all
                        width: parent.width
                        height: Theme.itemSizeSmall
                        onClicked: app.all = true
                        Label {
                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Show all %1").arg(app.modelData.actions.length)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.highlightColor
                        }
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
