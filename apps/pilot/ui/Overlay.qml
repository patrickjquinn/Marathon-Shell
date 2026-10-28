// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Pilot over any app: what the system-wide gesture (the gesture patch,
// shoal/pilot/lipstick/patch) brings up. A second window of the app
// (cpp/launcher.cpp, createOverlay), tagged CATEGORY=dialog so that
// Lipstick shows it above the app the person is in, which stays on screen
// behind a soft veil. The edges glow, the field and the mic wait at the
// bottom with the keyboard up, and what that app shows is the context
// ("summarise this"), with one-tap questions that fit it. Answers rise
// above the field, the turns since the overlay opened; the whole
// conversation is the app's (Conversation.qml), and "Open Pilot" carries
// on there. A tap on the veil, the close button or a swipe down puts the
// person back in their app.
//
// From the main QML: `show()` and `hide()`; `shown` says which.

pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Sailfish.Silica 1.0
import Keel 1.0
import Shipwright.Pilot 1.0
import "components"

Item {
    id: overlay
    objectName: "overlay"

    // The overlay's window and the app's main view (QQuickViews), set by
    // cpp/launcher.cpp once this has loaded; null in the desktop harness,
    // where the overlay is a plain item.
    property var window: null
    property var mainView: null

    property bool shown: false
    // The first entry of this session in the conversation.
    property int since: 0
    readonly property var now: Conversation.now
    readonly property string onScreen: now.on_screen || ""
    readonly property bool busy: Pilot.busy || Conversation.listening
    // The main page carries on: Open Pilot.
    signal expandRequested()

    // Lipstick reads the category when the window is first mapped, so it
    // is set as soon as the window is known, before the first show() (the
    // launcher created the platform window first).
    onWindowChanged: {
        if (window)
            Shell.setLipstickProperty(window, "CATEGORY", "dialog")
    }
    Component.onCompleted: Conversation.overlay = overlay

    function show() {
        Conversation.markGuide("gesture")
        input.text = ""
        since = Conversation.model.count
        session.refilter()
        shown = true
        if (window) {
            window.showFullScreen()
            window.requestActivate()
        }
        input.forceActiveFocus()
        Pilot.refreshNow()
    }

    function hide() {
        if (!shown)
            return
        shown = false
        input.focus = false
        hideLater.restart()
    }

    function expand() {
        hide()
        expandRequested()
    }

    // The keyboard goes down so that the answer has the room; a tap on
    // the field brings it back for the next question.
    function send(text) {
        if (text.trim().length === 0)
            return
        input.focus = false
        Conversation.send(text)
        input.text = ""
    }

    function listen() {
        input.focus = false
        Conversation.listen()
    }

    // The window goes once the veil has faded.
    Timer {
        id: hideLater
        interval: 220
        onTriggered: if (!overlay.shown && overlay.window) overlay.window.hide()
    }

    // Lipstick took the window away (an edge swipe to the home screen or
    // to another app): the overlay is done.
    Connections {
        target: overlay.window
        function onActiveChanged() { if (overlay.window && !overlay.window.active) leftTimer.restart() }
    }
    Timer {
        id: leftTimer
        interval: 400
        onTriggered: if (overlay.shown && overlay.window && !overlay.window.active && !Qt.inputMethod.visible) overlay.hide()
    }

    // The turns since the overlay opened.
    DelegateModel {
        id: session
        model: Conversation.model
        groups: DelegateModelGroup { id: recent; name: "recent" }
        filterOnGroup: "recent"
        delegate: Cards {
            onLook: overlay.expand()
            onOpenSettings: overlay.expand()
        }
        // The turns since `since`: earlier ones leave the group when the
        // overlay opens again.
        function refilter() {
            var n = items.count
            if (recent.count > 0 && overlay.since > 0)
                items.removeGroups(0, Math.min(overlay.since, n), "recent")
            if (n > overlay.since)
                items.addGroups(overlay.since, n - overlay.since, "recent")
        }
    }
    Connections {
        target: Conversation.model
        function onCountChanged() { session.refilter() }
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
        Behavior on opacity { FadeAnimator { duration: 200 } }

        readonly property real keyboard: Qt.inputMethod.visible
                                         ? (landscape ? Qt.inputMethod.keyboardRectangle.width
                                                      : Qt.inputMethod.keyboardRectangle.height)
                                         : 0

        // The app stays in view, dimmed; deeper behind the answers and
        // the field so they read over any page.
        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.overlayBackgroundColor, 0.3)
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height - stack.y + Theme.itemSizeLarge
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.rgba(Theme.overlayBackgroundColor, 0) }
                GradientStop { position: 0.12; color: Theme.rgba(Theme.overlayBackgroundColor, 0.82) }
                GradientStop { position: 1.0; color: Theme.rgba(Theme.overlayBackgroundColor, 0.94) }
            }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        // A tap on the app's part puts the person back in it.
        MouseArea {
            objectName: "veil"
            anchors.fill: parent
            onClicked: overlay.hide()
        }

        EdgeGlow {
            anchors.fill: parent
            active: overlay.shown
            intense: overlay.busy
        }

        // Answers above, then the questions that fit, then the field.
        Column {
            id: stack
            anchors {
                left: parent.left; right: parent.right
                bottom: parent.bottom; bottomMargin: content.keyboard + Theme.paddingMedium
            }
            spacing: Theme.paddingMedium

            // Sized to the cards (the few since it opened), up to most of
            // the screen above the field, with a strip of the app left to
            // tap. The newest card is shown from its top: a long answer is
            // read from its start, and scrolled for the rest.
            SilicaFlickable {
                id: turnsView
                width: parent.width
                height: Math.min(turnsColumn.height,
                                 content.height * 0.72 - content.keyboard - bar.height - Theme.paddingLarge)
                visible: turns.count > 0
                clip: true
                contentHeight: turnsColumn.height
                // From the latest question: it and the start of its answer.
                function showNewest() {
                    var top = 0
                    for (var i = turns.count - 1; i >= 0; --i) {
                        var item = turns.itemAt(i)
                        if (!item)
                            continue
                        top = item.y
                        if (Conversation.model.get(overlay.since + i).who === "you")
                            break
                    }
                    contentY = Math.max(0, Math.min(top, contentHeight - height))
                }
                onContentHeightChanged: showNewest()
                onHeightChanged: showNewest()
                Column {
                    id: turnsColumn
                    width: parent.width
                    spacing: Theme.paddingMedium
                    Repeater {
                        id: turns
                        objectName: "overlayTurns"
                        model: session
                    }
                }
                VerticalScrollDecorator {}
            }

            StageLine {
                objectName: "overlayStage"
                width: parent.width
                visible: Pilot.busy && !Conversation.listening
                running: visible
                stage: Conversation.stage
                detail: Conversation.stageDetail
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
                    color: Theme.highlightColor
                }
            }

            // Questions that fit what is on screen, before the first one.
            Flow {
                objectName: "overlayQuickAsks"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                spacing: Theme.paddingSmall
                visible: turns.count === 0 && !Conversation.listening && !Pilot.busy
                Repeater {
                    model: overlay.quickAsks()
                    delegate: Chip {
                        required property string modelData
                        text: modelData
                        onClicked: overlay.send(modelData)
                    }
                }
            }

            // The field: what Pilot sees, the words, and the mic.
            Rectangle {
                id: bar
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                height: barColumn.height + 2 * Theme.paddingSmall
                radius: Theme.paddingLarge
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.18)
                border.width: 1
                border.color: Theme.rgba(Theme.highlightColor, 0.35)

                // Swiping the field down closes the overlay (the answers
                // above scroll).
                DragHandler {
                    target: null
                    yAxis.enabled: true
                    xAxis.enabled: false
                    onActiveChanged: if (!active && translation.y > Theme.itemSizeMedium) overlay.hide()
                }

                Column {
                    id: barColumn
                    y: Theme.paddingSmall
                    width: parent.width

                    Row {
                        x: Theme.paddingMedium
                        width: parent.width - 2 * x
                        height: Theme.itemSizeSmall
                        spacing: Theme.paddingSmall
                        Orb {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSizeSmallPlus
                            height: width
                            mode: Pilot.busy ? "thinking" : "idle"
                        }
                        Label {
                            objectName: "overlayContext"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeSmallPlus - 2 * Theme.itemSizeSmall - 3 * Theme.paddingSmall
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.highlightColor
                            text: overlay.onScreen.length > 0 ? qsTr("Pilot · sees %1").arg(overlay.onScreen)
                                                              : qsTr("Pilot")
                        }
                        IconButton {
                            objectName: "overlayExpand"
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.itemSizeSmall
                            height: Theme.itemSizeSmall
                            icon.source: "image://theme/icon-m-up"
                            onClicked: overlay.expand()
                        }
                        IconButton {
                            objectName: "overlayClose"
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.itemSizeSmall
                            height: Theme.itemSizeSmall
                            icon.source: "image://theme/icon-m-clear"
                            onClicked: overlay.hide()
                        }
                    }

                    Row {
                        width: parent.width
                        TextField {
                            id: input
                            objectName: "overlayInput"
                            width: parent.width - (sendButton.visible ? sendButton.width : 0) - mic.width - Theme.paddingSmall
                            placeholderText: overlay.onScreen.length > 0 ? qsTr("Ask about this, or anything")
                                                                         : qsTr("Ask Pilot")
                            label: qsTr("Ask Pilot")
                            enabled: !Pilot.busy
                            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                            EnterKey.onClicked: overlay.send(text)
                        }
                        IconButton {
                            id: sendButton
                            visible: input.text.trim().length > 0
                            icon.source: "image://theme/icon-m-send"
                            enabled: !Pilot.busy
                            onClicked: overlay.send(input.text)
                        }
                        Orb {
                            id: mic
                            objectName: "overlayMic"
                            width: Theme.itemSizeMedium
                            height: Theme.itemSizeMedium
                            anchors.verticalCenter: input.verticalCenter
                            enabled: !Pilot.offline
                            glyph: true
                            mode: Conversation.listening && !Conversation.transcribing ? "listening"
                                  : Pilot.busy ? "thinking" : "idle"
                            level: Conversation.level
                            onClicked: overlay.listen()
                        }
                    }
                }
            }
        }
    }

    // One-tap questions: about the app on screen, or the home's.
    function quickAsks() {
        var app = onScreen.toLowerCase()
        if (app.length === 0)
            return (now.suggestions || []).slice(0, 3).map(function(s) { return s.text })
        if (app.indexOf("messages") >= 0 || app.indexOf("mail") >= 0)
            return [qsTr("Reply to this"), qsTr("Summarise this")]
        if (app.indexOf("pacific") >= 0 || app.indexOf("browser") >= 0)
            return [qsTr("Summarise this"), qsTr("Explain this simply"), qsTr("What are the key points?")]
        return [qsTr("Summarise this"), qsTr("What can I do here?")]
    }
}
