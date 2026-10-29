// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The turn view: the conversation, and the sheet at the bottom edge with
// the text field and the mic. Swiping up from the bottom edge opens the
// sheet when it is closed (inside the app only: a system-wide edge swipe
// needs Lipstick, see ../../README.md).

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0
import "../components"

Page {
    id: page
    objectName: "mainPage"

    // The conversation is the app's (Conversation.qml): the overlay over
    // other apps adds to the same one. These keep the page's own API.
    readonly property ListModel model: Conversation.model
    readonly property var now: Conversation.now
    readonly property bool listening: Conversation.listening
    readonly property bool transcribing: Conversation.transcribing
    property bool onboardingShown: false

    function send(text) {
        Conversation.send(text);
    }
    function answer(index, approved) {
        Conversation.answer(index, approved);
    }

    // The viewfinder is its own page, loaded only when used (it needs
    // QtMultimedia and the camera).
    function openCamera(question) {
        pageStack.push(Qt.resolvedUrl("CameraPage.qml"), {
            question: question
        });
    }

    // The system-wide gesture: the sheet up, ready to type.
    function openSheet() {
        sheet.open = true;
        input.forceActiveFocus();
        // Opened over another app: say which, from pilotd's Now.
        Pilot.refreshNow();
    }

    // Carried on from the overlay: the newest turn in view.
    function showLatest() {
        sheet.open = true;
        list.toEnd();
    }

    function listen() {
        if (Pilot.busy)
            return;
        sheet.open = true;
        input.focus = false;
        Conversation.listen();
    }

    Connections {
        target: Pilot
        function onConnectedChanged() {
            page.maybeOnboard();
            Pilot.refreshNow();
        }
    }
    Connections {
        target: Conversation
        function onGrew() {
            list.toEnd();
        }
    }

    // First run: the opt-in screen (spec section 10, "Consent"), once
    // pilotd answers.
    function maybeOnboard() {
        if (onboardingShown || status !== PageStatus.Active || !Pilot.connected)
            return;
        var s = JSON.parse(Pilot.settings());
        if (s.onboarded === false) {
            onboardingShown = true;
            pageStack.push(Qt.resolvedUrl("OnboardingDialog.qml"));
        }
    }
    onStatusChanged: {
        maybeOnboard();
        if (status === PageStatus.Active)
            Pilot.refreshNow();
    }
    // Keep the home current while it is shown (an alarm that rang, the
    // next event changing).
    Timer {
        interval: 60000
        repeat: true
        running: page.model.count === 0 && page.status === PageStatus.Active
        onTriggered: Pilot.refreshNow()
    }

    SilicaListView {
        id: list
        objectName: "conversation"
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: sheet.top
        }
        clip: true
        model: page.model
        spacing: Theme.paddingMedium

        header: Column {
            width: list.width
            // In a conversation: a plain header. Before one: the home.
            PageHeader {
                visible: list.count > 0
                title: qsTr("Pilot")
                description: Pilot.offline ? qsTr("Offline") : ""
            }
            Label {
                objectName: "offlineBanner"
                visible: Pilot.offline || Pilot.error.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: list.count > 0 ? 0 : Theme.paddingLarge
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                text: Pilot.error.length > 0 ? Pilot.error : qsTr("The privacy switch is on. Timers, alarms, reminders, media and the calendar still work.")
            }
            NowView {
                objectName: "nowView"
                visible: list.count === 0
                snapshot: page.now
                onAsk: function (question) {
                    page.send(question);
                }
                onOpenTriage: pageStack.push(Qt.resolvedUrl("TriagePage.qml"))
                onOpenLesson: function (step) {
                    pageStack.push(Qt.resolvedUrl("GuidePage.qml"), {
                        focusStep: step
                    });
                }
                onOpenCapabilities: pageStack.push(Qt.resolvedUrl("CapabilitiesPage.qml"))
            }
        }

        // The cards (Cards.qml).
        delegate: Cards {
            onLook: function (question) {
                page.openCamera(question);
            }
            onOpenSettings: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
        }

        // While pilotd works: what it is doing, where the answer will appear.
        footer: Item {
            width: list.width
            height: stageLine.visible ? stageLine.height : Theme.paddingMedium
            StageLine {
                id: stageLine
                objectName: "busyRow"
                visible: Pilot.busy && !page.listening
                running: visible
                stage: Conversation.stage
                detail: Conversation.stageDetail
            }
        }
        // Keep the newest card in view: a new card is laid out after it is
        // appended (its height is not known yet), and the keyboard opening
        // shortens the list; both move the end. Scrolling up to read stops
        // the following until the person is back at the end.
        property bool follow: true
        function toEnd() {
            follow = true;
            Qt.callLater(positionViewAtEnd);
        }
        onCountChanged: toEnd()
        onContentHeightChanged: if (follow)
            Qt.callLater(positionViewAtEnd)
        onHeightChanged: if (follow)
            Qt.callLater(positionViewAtEnd)
        onMovementEnded: follow = atYEnd

        PullDownMenu {
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Pilot events")
                onClicked: pageStack.push(Qt.resolvedUrl("TriagePage.qml"))
            }
            MenuItem {
                objectName: "learnMenuItem"
                text: qsTr("Learn Pilot")
                onClicked: pageStack.push(Qt.resolvedUrl("GuidePage.qml"))
            }
            MenuItem {
                objectName: "clearMenuItem"
                text: qsTr("Clear conversation")
                visible: page.model.count > 0
                onClicked: clearRemorse.execute(qsTr("Clearing conversation"), function () {
                    Conversation.clear();
                })
            }
        }

        ViewPlaceholder {
            enabled: page.model.count === 0 && !Pilot.busy && !page.now.greeting
            text: Pilot.offline ? qsTr("Pilot is offline") : qsTr("Ask Pilot")
            hintText: Pilot.offline ? qsTr("Timers, alarms, reminders, media and the calendar still work from text") : qsTr("Timers, alarms, reminders, music, your calendar, or any question")
        }
        VerticalScrollDecorator {}
    }

    RemorsePopup {
        id: clearRemorse
    }

    // Swipe up from the bottom edge to open a closed sheet.
    MouseArea {
        objectName: "edgeSwipe"
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: Theme.paddingLarge
        enabled: !sheet.open
        property real startY: 0
        onPressed: function (mouse) {
            startY = mouse.y;
        }
        onPositionChanged: function (mouse) {
            if (startY - mouse.y > Theme.paddingMedium)
                sheet.open = true;
        }
    }

    // While the microphone is open: the orb large in the middle of a soft
    // veil, and what is happening in words.
    Item {
        id: listeningPanel
        objectName: "listeningPanel"
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: sheet.top
        }
        opacity: page.listening ? 1 : 0
        visible: opacity > 0
        // An animation, not an animator: `visible` follows the opacity as
        // it changes.
        Behavior on opacity {
            FadeAnimation {
                duration: 250
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.45
                    color: Theme.rgba(Theme.overlayBackgroundColor, 0.55)
                }
                GradientStop {
                    position: 1.0
                    color: Theme.rgba(Theme.overlayBackgroundColor, 0.85)
                }
            }
        }
        MouseArea {
            anchors.fill: parent
        }   // the conversation waits

        Column {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Theme.itemSizeLarge
            }
            spacing: Theme.paddingLarge
            Orb {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.itemSizeHuge * 2
                height: width
                mode: page.transcribing ? "thinking" : "listening"
                level: Conversation.level
            }
            Label {
                objectName: "listeningText"
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.transcribing ? qsTr("Got it…") : qsTr("Listening…")
                font.pixelSize: Theme.fontSizeLarge
                font.family: Theme.fontFamilyHeading
                color: Theme.highlightColor
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.transcribing ? qsTr("Working out what you said, on this phone") : qsTr("Speak now. Pilot stops when you pause.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
        }
    }

    DockedPanel {
        id: sheet
        objectName: "sheet"
        width: parent.width
        height: sheetColumn.height + 2 * Theme.paddingMedium
        dock: Dock.Bottom
        open: true

        Column {
            id: sheetColumn
            y: Theme.paddingMedium
            width: parent.width
            spacing: Theme.paddingSmall

            // Opened over another app: its screen is the context of the
            // question ("summarise this"), until dismissed.
            Chip {
                objectName: "onScreenChip"
                x: Theme.horizontalPageMargin
                visible: !!page.now.on_screen
                iconSource: "image://theme/icon-m-clear"
                text: qsTr("Using what %1 shows").arg(page.now.on_screen || "")
                onClicked: {
                    Pilot.clearOnScreen();
                    Pilot.refreshNow();
                }
            }
            Row {
                width: parent.width
                TextField {
                    id: input
                    objectName: "input"
                    width: parent.width - (send.visible ? send.width : 0) - mic.width
                    placeholderText: qsTr("Ask Pilot")
                    label: qsTr("Ask Pilot")
                    enabled: !Pilot.busy
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: {
                        page.send(text);
                        text = "";
                    }
                }
                IconButton {
                    id: send
                    objectName: "sendButton"
                    visible: input.text.trim().length > 0
                    icon.source: "image://theme/icon-m-send"
                    enabled: !Pilot.busy
                    onClicked: {
                        page.send(input.text);
                        input.text = "";
                    }
                }
                // Tap to talk.
                Orb {
                    id: mic
                    objectName: "micButton"
                    width: Theme.itemSizeMedium
                    height: Theme.itemSizeMedium
                    anchors.verticalCenter: input.verticalCenter
                    enabled: !Pilot.offline
                    glyph: true
                    mode: page.listening && !page.transcribing ? "listening" : Pilot.busy ? "thinking" : "idle"
                    level: Conversation.level
                    onClicked: page.listen()
                }
            }
        }
    }
}
