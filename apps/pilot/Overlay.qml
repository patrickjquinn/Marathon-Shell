// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot over any app: what the system-wide gesture brings up. A second
// window of the app (PilotApp.qml), titled keel:dialog:pilot so that the
// compositor shows it above the app the person is in, which stays on screen
// behind the shell's backdrop. The edges glow, and a sheet rises from the
// bottom on the ambience, as the shell's own sheets do: what Pilot sees in
// its header, one-tap questions that fit it, then the field and the mic
// with the keyboard up. Answers grow the sheet upwards, the turns since the
// overlay opened; the whole conversation is the app's (Conversation.qml),
// and "Open Pilot" carries on there. A tap above the sheet, back or a swipe
// down puts the person back in their app.
//
// From the main QML: `show()` and `hide()`; `shown` says which.

pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Keel 1.0
import MarathonOS.Pilot 1.0
import "components"

Item {
    id: overlay
    objectName: "overlay"

    // The overlay's window; null in tests, where the overlay is a plain item.
    property var window: null

    property bool shown: false
    // The first entry of this session in the conversation.
    property int since: 0
    readonly property var now: Conversation.now
    readonly property string onScreen: now.on_screen || ""
    readonly property bool busy: Pilot.busy || Conversation.listening
    // The main page carries on: Open Pilot.
    signal expandRequested

    function show() {
        Conversation.markGuide("gesture");
        input.text = "";
        since = Conversation.model.count;
        session.refilter();
        shown = true;
        if (window) {
            window.showFullScreen();
            window.requestActivate();
        }
        input.forceActiveFocus();
        Pilot.refreshNow();
    }

    function hide() {
        if (!shown)
            return;
        shown = false;
        input.focus = false;
        hideLater.restart();
    }

    function expand() {
        hide();
        expandRequested();
    }

    // The keyboard goes down so that the answer has the room; a tap on
    // the field brings it back for the next question.
    function send(text) {
        if (text.trim().length === 0)
            return;
        overlay.forceActiveFocus();
        Conversation.send(text);
        input.text = "";
    }

    function listen() {
        overlay.forceActiveFocus();
        Conversation.listen();
    }

    // Swiping the sheet down closes the overlay, except over the answers,
    // which scroll.
    component SwipeDown: DragHandler {
        target: null
        xAxis.enabled: false
        onActiveTranslationChanged: if (activeTranslation.y > Theme.itemSizeMedium)
            overlay.hide()
    }

    // Escape, or the system back the shell sends the window as a key,
    // puts the person back in their app.
    Keys.onEscapePressed: overlay.hide()
    Keys.onBackPressed: overlay.hide()

    // The window goes once the overlay has faded.
    Timer {
        id: hideLater
        interval: 220
        onTriggered: if (!overlay.shown && overlay.window)
            overlay.window.hide()
    }

    // The shell took the window away (an edge swipe to the home screen or
    // to another app): the overlay is done.
    Connections {
        target: overlay.window
        function onActiveChanged() {
            if (overlay.window && !overlay.window.active)
                leftTimer.restart();
        }
    }
    Timer {
        id: leftTimer
        interval: 400
        onTriggered: if (overlay.shown && overlay.window && !overlay.window.active && !Qt.inputMethod.visible)
            overlay.hide()
    }

    // The turns since the overlay opened.
    DelegateModel {
        id: session
        model: Conversation.model
        groups: DelegateModelGroup {
            id: recent
            name: "recent"
        }
        filterOnGroup: "recent"
        delegate: Cards {
            sheet: true
            onLook: overlay.expand()
            onOpenSettings: overlay.expand()
        }
        // The turns since `since`: earlier ones leave the group when the
        // overlay opens again.
        function refilter() {
            var n = items.count;
            if (recent.count > 0 && overlay.since > 0)
                items.removeGroups(0, Math.min(overlay.since, n), "recent");
            if (n > overlay.since)
                items.addGroups(overlay.since, n - overlay.since, "recent");
        }
    }
    Connections {
        target: Conversation.model
        function onCountChanged() {
            session.refilter();
        }
    }

    // The overlay is laid out the way the app under it is held: Keel tells
    // every window of the app the screen's orientation (upside-down
    // portrait is not used, as in the main window).
    Item {
        id: content
        readonly property int degrees: Shell.orientation === 180 ? 0 : Shell.orientation
        readonly property bool landscape: degrees === 90 || degrees === 270
        anchors.centerIn: parent
        width: landscape ? overlay.height : overlay.width
        height: landscape ? overlay.width : overlay.height
        rotation: degrees
        opacity: overlay.shown ? 1 : 0
        Behavior on opacity {
            FadeAnimator {
                duration: 200
            }
        }

        readonly property real keyboard: Qt.inputMethod.visible ? (landscape ? Qt.inputMethod.keyboardRectangle.width : Qt.inputMethod.keyboardRectangle.height) : 0

        // A tap on the app's part puts the person back in it.
        MouseArea {
            objectName: "veil"
            anchors.fill: parent
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
            Accessible.onPressAction: overlay.hide()
            onClicked: overlay.hide()
        }

        EdgeGlow {
            anchors.fill: parent
            active: overlay.shown
            intense: overlay.busy
        }

        // The sheet, edge to edge on the ambience: the header, the answers,
        // the questions that fit, then the field.
        Item {
            id: sheet
            objectName: "overlaySheet"
            // A strip of the app is left to tap.
            readonly property real maximumHeight: content.height - content.keyboard - Theme.itemSizeLarge
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: content.keyboard
            }
            height: header.height + (turnsView.visible ? turnsView.height : 0) + lower.height
            Behavior on height {
                enabled: !Conversation.reduceMotion
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            // Taps on the sheet stay in it.
            MouseArea {
                anchors.fill: parent
            }

            Item {
                anchors.fill: parent
                clip: true
                Rectangle {
                    anchors.fill: parent
                    visible: ambience.status !== Image.Ready
                    color: Theme.highlightDimmerColor
                }
                // The slice of the ambience behind the sheet, toned as the
                // shell tones it behind apps.
                Image {
                    id: ambience
                    readonly property bool light: Theme.colorScheme === Theme.DarkOnLight
                    y: -sheet.y
                    width: content.width
                    height: content.height
                    smooth: true
                    cache: true
                    asynchronous: true
                    source: Theme._backgroundImage !== "" && width > 0 && height > 0 ? "image://keelambience/" + encodeURIComponent(Theme._backgroundImage) + "?w=" + Math.round(width) + "&h=" + Math.round(height) + (light ? "&tone=0.45&light=1" : "&tone=0.62&dim=" + Theme.highlightDimmerColor.toString().slice(1)) : ""
                }
            }
            Rectangle {
                width: parent.width
                height: Math.max(2, Math.round(Theme.paddingSmall / 4))
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.3
                        color: Theme.rgba(Theme.highlightColor, 0.3)
                    }
                    GradientStop {
                        position: 0.7
                        color: Theme.rgba(Theme.highlightColor, 0.3)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }

            PageHeader {
                id: header
                objectName: "overlayContext"
                title: qsTr("Pilot")
                description: overlay.onScreen.length > 0 ? qsTr("Sees %1").arg(overlay.onScreen) : ""
                Orb {
                    parent: header.extraContent
                    y: header.topMargin + (header.titleHeight - height) / 2
                    width: Theme.iconSizeSmallPlus
                    height: width
                    mode: Pilot.busy ? "thinking" : "idle"
                }
                SwipeDown {}
            }

            // Sized to the turns since it opened, up to the room left. The
            // newest is shown from its question: a long answer is read from
            // its start, and scrolled for the rest.
            SilicaFlickable {
                id: turnsView
                anchors.top: header.bottom
                width: parent.width
                height: Math.max(0, Math.min(turnsColumn.height, sheet.maximumHeight - header.height - lower.height))
                visible: turns.count > 0
                clip: true
                contentHeight: turnsColumn.height
                // From the latest question: it and the start of its answer.
                function showNewest() {
                    var top = 0;
                    for (var i = turns.count - 1; i >= 0; --i) {
                        var item = turns.itemAt(i);
                        if (!item)
                            continue;
                        top = item.y;
                        if (Conversation.model.get(overlay.since + i).who === "you")
                            break;
                    }
                    contentY = Math.max(0, Math.min(top, contentHeight - height));
                }
                onContentHeightChanged: showNewest()
                onHeightChanged: showNewest()
                Column {
                    id: turnsColumn
                    width: parent.width
                    Repeater {
                        id: turns
                        objectName: "overlayTurns"
                        model: session
                    }
                }
                VerticalScrollDecorator {}
            }

            Column {
                id: lower
                anchors.bottom: parent.bottom
                width: parent.width
                bottomPadding: Theme.paddingSmall
                SwipeDown {}

                StageLine {
                    objectName: "overlayStage"
                    width: parent.width
                    visible: Pilot.busy && !Conversation.listening
                    running: visible
                    stage: Conversation.stage
                    detail: Conversation.stageDetail
                    partial: Conversation.partial
                    read: Conversation.read
                    readLeft: Conversation.readLeft
                }

                // While the microphone is open: the orb, and what is happening.
                Column {
                    width: parent.width
                    visible: Conversation.listening
                    spacing: Theme.paddingSmall
                    Orb {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.itemSizeHuge
                        height: width
                        mode: Conversation.transcribing ? "thinking" : "listening"
                        level: Conversation.level
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Conversation.transcribing ? qsTr("Got it…") : qsTr("Listening…")
                        font.pixelSize: Theme.fontSizeLarge
                        font.family: Theme.fontFamilyHeading
                        color: Theme.primaryColor
                    }
                }

                // Questions that fit what is on screen, before the first one.
                Column {
                    objectName: "overlayQuickAsks"
                    width: parent.width
                    visible: turns.count === 0 && !Conversation.listening && !Pilot.busy
                    Repeater {
                        model: overlay.quickAsks()
                        delegate: SuggestionTile {
                            id: quickAsk
                            required property var modelData
                            objectName: "overlayQuickAsk"
                            width: parent ? parent.width : 0
                            text: quickAsk.modelData.text
                            icon: quickAsk.modelData.icon
                            onClicked: overlay.send(quickAsk.modelData.text)
                        }
                    }
                }

                // Carries on in Pilot.
                SuggestionTile {
                    objectName: "overlayExpand"
                    width: parent.width
                    visible: turns.count > 0 && !Conversation.listening
                    text: qsTr("Open Pilot")
                    icon: "open"
                    onClicked: overlay.expand()
                }

                // The words, and the mic.
                Row {
                    width: parent.width
                    rightPadding: Theme.paddingMedium
                    // Grows with the question, then scrolls; no label band.
                    TextArea {
                        id: input
                        objectName: "overlayInput"
                        width: parent.width - parent.rightPadding - (sendButton.visible ? sendButton.width : 0) - (stopButton.visible ? stopButton.width : 0) - (mic.visible ? mic.width : 0)
                        height: Math.min(implicitHeight, Screen.height / 4)
                        placeholderText: overlay.onScreen.length > 0 ? qsTr("Ask about this, or anything") : qsTr("Ask Pilot")
                        labelVisible: false
                        // Enter sends and its key also gave a new line: an empty field
                        // with the cursor on its second. Only blank, it is empty.
                        onTextChanged: if (text.length > 0 && text.trim() === "")
                            text = ""
                        EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                        EnterKey.onClicked: overlay.send(text)
                        // Enter sends; Shift+Enter is a new line.
                        Keys.onReturnPressed: function (event) {
                            event.accepted = !(event.modifiers & Qt.ShiftModifier);
                            if (event.accepted)
                                overlay.send(text);
                        }
                        Keys.onUpPressed: function (event) {
                            event.accepted = text === "" && Conversation.lastQuestion() !== "";
                            if (event.accepted)
                                text = Conversation.lastQuestion();
                        }
                    }
                    IconButton {
                        id: sendButton
                        objectName: "overlaySend"
                        Accessible.name: qsTr("Send")
                        visible: input.text.trim().length > 0
                        anchors.bottom: input.bottom
                        icon.source: "image://theme/icon-m-send"
                        onClicked: overlay.send(input.text)
                    }
                    StopButton {
                        id: stopButton
                        objectName: "overlayStop"
                        visible: Pilot.busy && !Conversation.listening
                        anchors.bottom: input.bottom
                        onClicked: Pilot.stop()
                    }
                    Orb {
                        id: mic
                        objectName: "overlayMic"
                        visible: Conversation.voiceAvailable
                        width: Theme.itemSizeMedium
                        height: Theme.itemSizeMedium
                        anchors.bottom: input.bottom
                        enabled: !Pilot.offline
                        glyph: true
                        mode: Conversation.listening && !Conversation.transcribing ? "listening" : Pilot.busy ? "thinking" : "idle"
                        level: Conversation.level
                        onClicked: overlay.listen()
                    }
                }
            }
        }
    }

    // One-tap questions: about the app on screen, or the home's.
    function quickAsks() {
        var app = onScreen.toLowerCase();
        if (app.length === 0)
            return (now.suggestions || []).slice(0, 3);
        if (app.indexOf("messages") >= 0 || app.indexOf("mail") >= 0)
            return [
                {
                    text: qsTr("Reply to this"),
                    icon: "reply"
                },
                {
                    text: qsTr("Summarise this"),
                    icon: "summary"
                }
            ];
        if (app.indexOf("pacific") >= 0 || app.indexOf("browser") >= 0)
            return [
                {
                    text: qsTr("Summarise this"),
                    icon: "summary"
                },
                {
                    text: qsTr("Explain this simply"),
                    icon: "explain"
                },
                {
                    text: qsTr("What are the key points?"),
                    icon: "points"
                }
            ];
        return [
            {
                text: qsTr("Summarise this"),
                icon: "summary"
            },
            {
                text: qsTr("What can I do here?"),
                icon: "explore"
            }
        ];
    }
}
