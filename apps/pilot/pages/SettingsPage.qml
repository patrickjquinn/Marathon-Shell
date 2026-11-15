// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// What Pilot may use, what it remembers, the egress log, data export and
// wipe (spec section 8.2, "Settings"). Pilot answers on the phone, so
// answering questions is not a choice here.

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Pilot 1.0
import "../components"

Page {
    id: page
    objectName: "settingsPage"

    property var settings: ({
            consent: {}
        })
    property string message: ""
    // What Export or Delete did, shown under their buttons.
    property string dataMessage: ""
    // Controls take their values while the page builds; only later changes
    // are sent to pilotd.
    property bool ready: false
    property var memories: []
    // A deep link's section: "memories", or "" for the top.
    property string startAt: ""
    // Bytes of the speech models pilot-voice downloaded (-1: unknown).
    property real voiceModelsBytes: -1

    function megabytes(b) {
        return Math.max(1, Math.round(b / 1000000));
    }

    // Pilot's voice (the Piper voice it ships) is English; speech
    // recognition follows the phone's language.
    readonly property string englishVoiceNote: Qt.locale().name.indexOf("en") === 0 ? "" : " " + qsTr("Pilot speaks its answers in English for now.")

    readonly property var capabilities: [
        {
            voice: true,
            name: "voice_cloud",
            label: qsTr("Spoken questions"),
            description: qsTr("Your speech is turned into text on this phone and answered like a typed question.") + englishVoiceNote
        },
        {
            name: "vision",
            label: qsTr("Camera questions"),
            description: qsTr("Pilot looks at a smaller copy of the photo you take, on this phone, without its location, and then deletes it.")
        },
        {
            name: "triage",
            label: qsTr("Notification sorting"),
            description: qsTr("New notifications, messages and calendar changes are sorted into Pilot events.")
        },
        {
            voice: true,
            name: "spoken_nudges",
            label: qsTr("Spoken nudges"),
            description: qsTr("Pilot may speak when something urgent arrives.") + englishVoiceNote
        },
        {
            name: "history",
            label: qsTr("Conversation history"),
            description: qsTr("Your conversations stay on this phone for 30 days, so you can ask Pilot about them later. Turning this off deletes them.")
        }
    ]

    function reload() {
        var s = JSON.parse(Pilot.settings());
        if (s.error !== undefined) {
            message = s.error;
            return;
        }
        settings = s;
    }

    // Errors stay on the page; a confirmation is a notice (Silica's
    // transient feedback).
    function report(err, done) {
        message = err;
        if (!err.length && done.length)
            Notices.show(done, Notice.Short);
        reload();
    }

    Component.onCompleted: {
        reload();
        memories = JSON.parse(Pilot.memories());
        if (Conversation.voiceAvailable)
            voiceModelsBytes = Pilot.voiceModelsBytes();
        ready = true;
    }

    onStatusChanged: {
        if (status !== PageStatus.Active || startAt !== "memories")
            return;
        flick.contentY = Math.max(0, Math.min(memoriesHeader.y, flick.contentHeight - flick.height));
        startAt = "";
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge * 2

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Pilot settings")
            }

            Label {
                objectName: "settingsMessage"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                visible: text.length > 0
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primaryColor
                text: page.message
            }

            SectionHeader {
                text: qsTr("You")
            }
            TextField {
                objectName: "nameField"
                width: parent.width
                label: qsTr("What Pilot calls you, on its home")
                placeholderText: qsTr("Your name (optional)")
                text: page.settings.name || ""
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
                onActiveFocusChanged: if (!activeFocus && page.ready && text !== (page.settings.name || ""))
                    page.report(Pilot.setName(text), qsTr("Saved."))
            }
            Button {
                objectName: "introButton"
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Show the introduction")
                onClicked: pageStack.push(Qt.resolvedUrl("OnboardingDialog.qml"), {
                    again: true
                })
            }

            SectionHeader {
                id: memoriesHeader
                text: qsTr("What Pilot remembers")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: page.memories.length === 0
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                text: qsTr("Nothing yet. Say “remember that …” and Pilot keeps it here, on this phone.")
            }
            Repeater {
                model: page.memories
                delegate: ListItem {
                    id: memoryItem
                    required property var modelData
                    contentHeight: Math.max(Theme.itemSizeSmall, memoryText.height + 2 * Theme.paddingMedium)
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Forget")
                            onClicked: {
                                Pilot.forget(memoryItem.modelData.id);
                                page.memories = JSON.parse(Pilot.memories());
                            }
                        }
                    }
                    Label {
                        id: memoryText
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        text: memoryItem.modelData.fact
                    }
                }
            }

            SectionHeader {
                text: qsTr("What Pilot may use")
            }
            Repeater {
                model: page.capabilities.filter(function (c) {
                    return !c.voice || Conversation.voiceAvailable;
                })
                TextSwitch {
                    id: consentSwitch
                    required property var modelData
                    objectName: "consent_" + consentSwitch.modelData.name
                    text: consentSwitch.modelData.label
                    description: consentSwitch.modelData.description
                    checked: page.settings.consent[consentSwitch.modelData.name] === true
                    onCheckedChanged: {
                        var name = consentSwitch.modelData.name;
                        if (!page.ready || checked === (page.settings.consent[name] === true))
                            return;
                        page.report(Pilot.setConsent(name, checked), "");
                    }
                }
            }

            SectionHeader {
                text: qsTr("Your data")
            }
            BackgroundItem {
                id: egressLink
                objectName: "egressLink"
                width: parent.width
                // As tall as its lines need at a large text size.
                height: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
                onClicked: pageStack.push(Qt.resolvedUrl("EgressLogPage.qml"))
                Column {
                    id: rowText
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        color: egressLink.highlighted ? Theme.highlightColor : Theme.primaryColor
                        text: qsTr("What left this phone")
                    }
                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: egressLink.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        text: qsTr("Each request: when, where to, how much")
                    }
                }
            }
            Item {
                width: 1
                height: Theme.paddingLarge
            }
            // Stacked, as Jolla Settings stacks its page actions.
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                Button {
                    objectName: "exportButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: qsTr("Export")
                    onClicked: {
                        var path = Pilot.defaultExportPath();
                        var err = Pilot.exportTo(path);
                        page.dataMessage = err.length ? err : qsTr("Saved to %1").arg(path);
                    }
                }
                Button {
                    objectName: "wipeButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: qsTr("Delete records")
                    onClicked: remorse.execute(qsTr("Deleting Pilot's records"), function () {
                        var err = Pilot.wipe();
                        page.dataMessage = err;
                        if (!err.length)
                            Notices.show(qsTr("Pilot's records deleted"), Notice.Short);
                    })
                }
            }
            // The speech models are downloaded, not installed: removing
            // the app leaves them, so they are removed here.
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: Conversation.voiceAvailable && page.voiceModelsBytes > 0
                topPadding: Theme.paddingLarge
                Label {
                    objectName: "voiceModelsLabel"
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: qsTr("Downloaded voice models: %1 MB. Removing Pilot does not remove them; remove them here first. Pilot downloads one again the next time you speak to it.").arg(page.megabytes(page.voiceModelsBytes))
                }
                Button {
                    objectName: "removeVoiceModelsButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: qsTr("Remove downloaded voice models")
                    onClicked: remorse.execute(qsTr("Removing voice models"), function () {
                        var err = Pilot.removeVoiceModels();
                        page.dataMessage = err;
                        page.voiceModelsBytes = Pilot.voiceModelsBytes();
                        if (!err.length)
                            Notices.show(qsTr("Voice models removed"), Notice.Short);
                    })
                }
            }
            Label {
                objectName: "dataMessage"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: page.dataMessage.length > 0 ? Theme.fontSizeSmall : Theme.fontSizeExtraSmall
                color: page.dataMessage.length > 0 ? Theme.primaryColor : Theme.secondaryColor
                text: page.dataMessage.length > 0 ? page.dataMessage : qsTr("Export saves the log of what left this phone to Downloads. Delete removes the log and the conversation.")
            }
        }
        VerticalScrollDecorator {}
    }

    RemorsePopup {
        id: remorse
    }
}
