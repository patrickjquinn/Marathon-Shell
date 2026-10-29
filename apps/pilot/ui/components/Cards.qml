// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The delegate of a conversation view, for the main page and the overlay.
// Pilot's typed cards (a timer, an alarm, a reminder, an agenda, an
// answer) have their own designs, filled from the card's JSON; everything
// else (what you said, a question back, a confirmation) is a TurnCard,
// whose properties are named after the model's roles. What leaves the view
// (the camera, Settings) is up to the view.

pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.qmlmodels

DelegateChooser {
    id: cards

    // "Look with the camera" on a question back, and the Settings link.
    signal look(string question)
    signal openSettings

    role: "kind"
    DelegateChoice {
        roleValue: "timer"
        TimerCard {
            required property string payload
            readonly property var c: JSON.parse(payload)
            cookie: c.cookie
            seconds: c.seconds
            endsAt: c.ends_at
            label: c.label || ""
        }
    }
    DelegateChoice {
        roleValue: "alarm"
        ClockCard {
            required property string payload
            readonly property var c: JSON.parse(payload)
            kind: "alarm"
            cookie: c.cookie
            at: c.at
            title: c.label || ""
        }
    }
    DelegateChoice {
        roleValue: "reminder"
        ClockCard {
            required property string payload
            readonly property var c: JSON.parse(payload)
            kind: "reminder"
            cookie: c.cookie
            at: c.at
            title: c.what
        }
    }
    DelegateChoice {
        roleValue: "confirm"
        PlanCard {
            required property int index
            required property string payload
            required property bool allowed
            required answered
            readonly property var c: JSON.parse(payload)
            title: c.title || ""
            detail: c.detail || ""
            steps: c.steps || []
            outbound: !!c.outbound
            destructive: !!c.destructive
            approved: allowed
            onAnswer: function (approved) {
                Conversation.answer(index, approved);
            }
        }
    }
    DelegateChoice {
        roleValue: "memory"
        MemoryCard {
            required property string payload
            readonly property var c: JSON.parse(payload)
            text: c.text
            action: c.action
            facts: c.facts || []
        }
    }
    DelegateChoice {
        roleValue: "agenda"
        AgendaCard {
            required property string payload
            readonly property var c: JSON.parse(payload)
            range: c.range
            events: c.events
        }
    }
    // Pilot's plain replies (a handler's confirmation, an error from
    // an action) look like its answers.
    DelegateChoice {
        roleValue: "response"
        AnswerCard {
            required text
            required via
            required ms
        }
    }
    DelegateChoice {
        roleValue: "answer"
        AnswerCard {
            required property string payload
            required via
            required ms
            readonly property var c: JSON.parse(payload)
            text: c.text
            sources: c.sources || []
            how: c.how || []
            followups: c.followups || []
            onAsk: function (question) {
                Conversation.send(question);
            }
        }
    }
    DelegateChoice {
        TurnCard {
            required property int index
            required property string time
            required property bool allowed
            stamp: time
            approved: allowed
            onAnswer: function (approved) {
                Conversation.answer(index, approved);
            }
            onLook: function (question) {
                Conversation.model.setProperty(index, "answered", true);
                cards.look(question);
            }
            onOpenSettings: cards.openSettings()
        }
    }
}
