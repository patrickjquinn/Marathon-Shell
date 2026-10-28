// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot's home, before anything is asked: a greeting and the date, what
// is running (timers counting down, the next alarm, reminders), what is
// next in the calendar, what needs the person (triage), and questions
// that fit the moment, one tap each; for a new user, the getting-started
// guide first. All of it read on the phone
// (pilotd's Now), so it is there as soon as the app opens.

import QtQuick
import Sailfish.Silica 1.0

Column {
    id: now

    // pilotd's `Now` JSON, parsed.
    property var snapshot: ({})
    signal ask(string question)
    signal openTriage()
    signal openLesson(string step)
    signal openCapabilities()

    readonly property var clock: snapshot.clock || []
    readonly property var timers: clock.filter(function(c) { return c.kind === "timer" })
    readonly property var alarms: clock.filter(function(c) { return c.kind !== "timer" })
    readonly property var events: snapshot.events || []
    readonly property var attention: snapshot.attention || []
    readonly property var suggestions: snapshot.suggestions || []

    width: parent ? parent.width : 0
    spacing: Theme.paddingLarge
    bottomPadding: Theme.paddingLarge

    // The greeting, large and light, as the stock apps' first screens.
    Column {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * x
        topPadding: Theme.itemSizeLarge
        bottomPadding: Theme.paddingMedium
        Label {
            objectName: "nowGreeting"
            width: parent.width
            text: now.snapshot.greeting || ""
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeHuge
            font.family: Theme.fontFamilyHeading
            color: Theme.highlightColor
        }
        Label {
            width: parent.width
            text: now.snapshot.offline ? qsTr("%1 · Offline").arg(now.snapshot.date || "") : (now.snapshot.date || "")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryHighlightColor
        }
    }

    // Getting to know Pilot, until every skill has been tried or the
    // guide is put away.
    GuideCard {
        visible: Conversation.guide.indexOf("hidden") < 0
                 && Conversation.guideDone < Conversation.guideSteps.length
        onOpenLesson: function(step) { now.openLesson(step) }
        onOpenCapabilities: now.openCapabilities()
    }

    // Running: timers counting down first, then alarms and reminders.
    Repeater {
        model: now.timers
        delegate: TimerCard {
            id: timerCard
            required property var modelData
            cookie: timerCard.modelData.cookie
            seconds: timerCard.modelData.seconds || Math.max(1, timerCard.modelData.at - Date.now() / 1000)
            endsAt: timerCard.modelData.at
            label: timerCard.modelData.title.indexOf(" timer") > 0 ? "" : timerCard.modelData.title
        }
    }
    Repeater {
        model: now.alarms
        delegate: ClockCard {
            id: clockCard
            required property var modelData
            kind: clockCard.modelData.kind
            cookie: clockCard.modelData.cookie
            at: clockCard.modelData.at
            title: clockCard.modelData.title
        }
    }

    // Next in the calendar.
    AgendaCard {
        visible: now.events.length > 0
        range: "next"
        events: now.events
    }

    // Needs you: triage that is due now or today.
    Glass {
        visible: now.attention.length > 0
        accent: true
        Row {
            spacing: Theme.paddingMedium
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeSmallPlus
                height: width
                source: "image://theme/icon-m-events"
                color: Theme.highlightColor
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Needs you")
                color: Theme.highlightColor
            }
        }
        Repeater {
            model: now.attention
            delegate: Label {
                id: attentionRow
                required property var modelData
                width: parent ? parent.width : 0
                text: (attentionRow.modelData.app ? attentionRow.modelData.app + ": " : "")
                      + attentionRow.modelData.title
                truncationMode: TruncationMode.Fade
                color: Theme.highlightColor
            }
        }
        Chip {
            text: qsTr("Open Pilot events")
            secondary: true
            onClicked: now.openTriage()
        }
    }

    // Try asking: four tiles, two by two.
    Column {
        visible: now.suggestions.length > 0
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * x
        spacing: Theme.paddingMedium
        topPadding: Theme.paddingMedium
        Label {
            text: qsTr("Try asking")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
        }
        Grid {
            id: tiles
            width: parent.width
            columns: 2
            spacing: Theme.paddingMedium
            Repeater {
                model: now.suggestions
                delegate: SuggestionTile {
                    id: suggestion
                    required property var modelData
                    objectName: "suggestion"
                    width: parent ? (parent.width - Theme.paddingMedium) / 2 : 0
                    text: suggestion.modelData.text
                    icon: suggestion.modelData.icon
                    onClicked: now.ask(suggestion.modelData.text)
                }
            }
        }
    }
}
