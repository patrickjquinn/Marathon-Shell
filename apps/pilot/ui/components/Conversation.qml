// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The conversation, one for the app: the main page shows all of it, and
// the overlay over other apps (Overlay.qml, a second window in the same
// QML engine) shows the turns since it opened. Both send through here, so
// a question asked over an app is in the conversation when Pilot opens.

pragma Singleton

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

QtObject {
    id: conversation

    readonly property ListModel model: ListModel {}
    // The home (pilotd's Now) and the stage of the turn in progress.
    property var now: ({})
    property string stage: "thinking"
    property string stageDetail: ""
    // A spoken turn: listening (the microphone is open), then the words
    // being recognised; `level` is the voice, 0 to 1.
    property bool listening: false
    property bool transcribing: false
    property real level: 0
    // The overlay over other apps (Overlay.qml), when the app has one.
    property Item overlay: null
    // The getting-started guide (GuideCard.qml, GuidePage.qml): the skills
    // tried, kept by pilotd ("gesture", "screen", "voice", "action",
    // "how"; "hidden" once put away). Each is marked when the person does
    // it, not when they read about it.
    property var guide: []
    readonly property var guideSteps: ["gesture", "screen", "voice", "action", "how"]
    readonly property int guideDone: guideSteps.filter(function (g) {
        return guide.indexOf(g) >= 0;
    }).length

    function loadGuide() {
        var s = JSON.parse(Pilot.settings() || "{}");
        guide = s.guide || [];
    }
    function markGuide(step) {
        if (guide.indexOf(step) >= 0)
            return;
        Pilot.setGuide(step, true);
        guide = guide.concat([step]);
    }

    // Entries were added: the views bring the newest into view.
    signal grew

    // Every entry has every role (a ListModel takes its roles from the
    // first one): who said it, the card, when, and how a confirmation was
    // answered.
    function entry(fields) {
        var e = {
            who: "pilot",
            kind: "response",
            text: "",
            title: "",
            detail: "",
            cardId: "",
            outbound: false,
            destructive: false,
            answered: false,
            allowed: false,
            payload: "",
            via: "",
            ms: 0,
            time: Format.formatDate(new Date(), Formatter.TimeValue)
        };
        for (var k in fields)
            e[k] = fields[k];
        return e;
    }

    function addCards(result) {
        listening = false;
        transcribing = false;
        level = 0;
        if (result.transcript !== undefined && result.transcript.length > 0)
            model.append(entry({
                who: "you",
                kind: "you",
                text: result.transcript
            }));
        if (result.error !== undefined) {
            model.append(entry({
                kind: "error",
                text: result.error
            }));
            grew();
            return;
        }
        // A declined confirmation: its card already says Cancelled.
        if (result.route === "declined")
            return;
        for (var i = 0; i < result.cards.length; ++i) {
            var c = result.cards[i];
            if (["timer", "alarm", "reminder", "confirm", "agenda", "memory"].indexOf(c.kind) >= 0)
                markGuide("action");
            var last = i === result.cards.length - 1;
            model.append(entry({
                kind: c.kind,
                text: c.text || "",
                title: c.title || "",
                detail: c.detail || c.question || "",
                cardId: c.id || "",
                outbound: !!c.outbound,
                destructive: !!c.destructive,
                payload: JSON.stringify(c),
                via: last ? (result.via || "") : "",
                ms: last ? (result.ms || 0) : 0
            }));
        }
        stage = "thinking";
        stageDetail = "";
        grew();
        Pilot.refreshNow();
    }

    function send(text) {
        text = text.trim();
        if (text.length === 0 || Pilot.busy)
            return;
        model.append(entry({
            who: "you",
            kind: "you",
            text: text
        }));
        grew();
        if (now.on_screen)
            markGuide("screen");
        Pilot.ask(text, false);
    }

    function answer(index, approved) {
        var e = model.get(index);
        if (e.answered)
            return;
        model.setProperty(index, "allowed", approved);
        model.setProperty(index, "answered", true);
        Pilot.confirm(e.cardId, approved);
    }

    function listen() {
        if (Pilot.busy)
            return;
        listening = true;
        markGuide("voice");
        Pilot.listen();
    }

    // A new conversation: on screen, and as context for Pilot's next answer.
    function clear() {
        model.clear();
        Pilot.clearConversation();
        Pilot.refreshNow();
    }

    Component.onCompleted: if (Pilot.connected)
        loadGuide()

    readonly property Connections _pilot: Connections {
        target: Pilot
        function onTurnFinished(json) {
            conversation.addCards(JSON.parse(json));
        }
        function onWiped() {
            conversation.model.clear();
        }
        function onNowChanged(json) {
            conversation.now = JSON.parse(json);
        }
        function onConnectedChanged() {
            if (Pilot.connected)
                conversation.loadGuide();
        }
        function onTurnProgress(json) {
            var p = JSON.parse(json);
            if (p.stage === "level") {
                conversation.level = parseFloat(p.detail) || 0;
                return;
            }
            if (p.stage === "listening") {
                conversation.listening = true;
                conversation.transcribing = false;
                return;
            }
            if (p.stage === "transcribing") {
                conversation.transcribing = true;
                conversation.level = 0;
                return;
            }
            conversation.listening = false;
            conversation.transcribing = false;
            conversation.stage = p.stage;
            conversation.stageDetail = p.detail || "";
        }
    }
}
