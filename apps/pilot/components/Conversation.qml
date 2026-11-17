// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The conversation, one for the app: the main page shows all of it, and
// the overlay over other apps (Overlay.qml, a second window in the same
// QML engine) shows the turns since it opened. Both send through here, so
// a question asked over an app is in the conversation when Pilot opens.

pragma Singleton

import QtQuick
import Sailfish.Silica 1.0
import Nemo.Ngf 1.0
import MarathonOS.Pilot 1.0

QtObject {
    id: conversation

    readonly property ListModel model: ListModel {}
    // The home (pilotd's Now) and the stage of the turn in progress.
    property var now: ({})
    property string stage: "thinking"
    property string stageDetail: ""
    // The answer so far, while the model on the phone writes it.
    property string partial: ""
    // How much of the request the model on the phone has read before it
    // writes (0 to 1; -1 when it is not reading), and the milliseconds
    // left at its rate so far.
    property real read: -1
    property real readLeft: 0
    // A spoken turn: listening (the microphone is open), then the words
    // being recognised; `level` is the voice, 0 to 1.
    property bool listening: false
    property bool transcribing: false
    property real level: 0
    // Text another app shared ("Ask Pilot about this"): it goes with the
    // next question.
    property string shared: ""
    // Questions asked while Pilot was answering, oldest first.
    property var queued: []
    // Settings > Accessibility > Reduce motion: the orb, the glow and the
    // activity dots stand still.
    // qmllint disable unqualified
    property bool reduceMotion: typeof MarathonA11ySettings !== "undefined" && MarathonA11ySettings !== null && MarathonA11ySettings.reduceMotion === true
    // qmllint enable unqualified
    // The getting-started guide (GuideCard.qml, GuidePage.qml): the skills
    // tried, kept by pilotd ("gesture", "screen", "voice", "action",
    // "how"; "hidden" once put away). Each is marked when the person does
    // it, not when they read about it.
    property var guide: []
    readonly property var guideSteps: voiceAvailable ? ["gesture", "screen", "voice", "action", "how"] : ["gesture", "screen", "action", "how"]
    // Whether pilotd can listen (its VoiceAvailable): every voice surface
    // stays hidden without it.
    readonly property bool voiceAvailable: Pilot.voiceAvailable
    readonly property int guideDone: guideSteps.filter(function (g) {
        return guide.indexOf(g) >= 0;
    }).length

    function loadSettings() {
        var s = JSON.parse(Pilot.settings() || "{}");
        guide = s.guide || [];
    }
    function markGuide(step) {
        if (guide.indexOf(step) >= 0)
            return;
        Pilot.setGuide(step, true);
        guide = guide.concat([step]);
    }

    // A question sent, a confirmation answered; a firmer one when that lets
    // Pilot delete or send.
    readonly property NonGraphicalFeedback _press: NonGraphicalFeedback {
        event: "feedback_press"
    }
    readonly property NonGraphicalFeedback _commit: NonGraphicalFeedback {
        event: "feedback_lock"
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
            code: "",
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
        // A failed turn has a typed error card; an older pilotd's failure
        // is only its message.
        if (result.cards === undefined)
            result.cards = [
                {
                    kind: "error",
                    code: "internal",
                    text: String(result.error || "")
                }
            ];
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
                code: c.code || "",
                via: last ? (result.via || "") : "",
                ms: last ? (result.ms || 0) : 0
            }));
        }
        stage = "thinking";
        stageDetail = "";
        read = -1;
        grew();
        Pilot.refreshNow();
    }

    // Asked while Pilot is still answering, a question waits its turn.
    function send(text) {
        text = text.trim();
        if (text.length === 0)
            return;
        model.append(entry({
            who: "you",
            kind: "you",
            text: text
        }));
        _press.play();
        grew();
        if (now.on_screen)
            markGuide("screen");
        var question = shared.length > 0 ? text + "\n\n" + shared : text;
        shared = "";
        if (Pilot.busy)
            queued = queued.concat([question]);
        else
            Pilot.ask(question, false);
    }

    // The person's latest question, for the field's Up key.
    function lastQuestion() {
        for (var i = model.count - 1; i >= 0; --i) {
            if (model.get(i).who === "you")
                return model.get(i).text;
        }
        return "";
    }

    function askQueued() {
        if (queued.length === 0 || Pilot.busy)
            return;
        var next = queued[0];
        queued = queued.slice(1);
        Pilot.ask(next, false);
    }

    function answer(index, approved) {
        var e = model.get(index);
        if (e.answered)
            return;
        model.setProperty(index, "allowed", approved);
        model.setProperty(index, "answered", true);
        (approved && (e.destructive || e.outbound) ? _commit : _press).play();
        Pilot.confirm(e.cardId, approved);
    }

    // Try again: the question the failed card answered, asked anew.
    function retry(index) {
        model.setProperty(index, "answered", true);
        for (var i = index - 1; i >= 0; --i) {
            if (model.get(i).who === "you") {
                send(model.get(i).text);
                return;
            }
        }
    }

    function listen() {
        if (Pilot.busy || !voiceAvailable)
            return;
        listening = true;
        markGuide("voice");
        Pilot.listen();
    }

    // A new conversation: on screen, and as context for Pilot's next answer.
    function clear() {
        model.clear();
        queued = [];
        Pilot.clearConversation();
        Pilot.refreshNow();
    }

    Component.onCompleted: if (Pilot.connected)
        loadSettings()

    readonly property Connections _pilot: Connections {
        target: Pilot
        function onTurnFinished(json) {
            conversation.partial = "";
            conversation.addCards(JSON.parse(json));
            conversation.askQueued();
        }
        function onWiped() {
            conversation.model.clear();
            conversation.queued = [];
        }
        function onNowChanged(json) {
            conversation.now = JSON.parse(json);
        }
        function onConnectedChanged() {
            if (Pilot.connected)
                conversation.loadSettings();
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
            if (p.stage === "read") {
                var r = (p.detail || "").split(" ");
                conversation.readLeft = parseFloat(r[1]) || 0;
                conversation.read = parseFloat(r[0]) || 0;
                return;
            }
            conversation.read = -1;
            if (p.stage === "partial") {
                conversation.stage = "writing";
                conversation.partial = p.detail || "";
                return;
            }
            // A tool round follows what was written so far: it was not
            // the answer.
            conversation.partial = "";
            conversation.stage = p.stage;
            conversation.stageDetail = p.detail || "";
        }
    }
}
