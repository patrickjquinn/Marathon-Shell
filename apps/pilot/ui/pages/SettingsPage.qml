// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Per-capability cloud consent, backend choice, the egress log, data
// export and wipe (spec section 8.2, "Settings").

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Page {
    id: page
    objectName: "settingsPage"

    property var settings: ({ consent: {}, backends: [], backend: "standard" })
    property string message: ""
    // What Export or Delete did, shown under their buttons.
    property string dataMessage: ""
    // Controls take their values while the page builds; only later changes
    // are sent to pilotd.
    property bool ready: false
    property var memories: []
    // Bytes of the speech models pilot-voice downloaded (-1: unknown).
    property real voiceModelsBytes: -1

    function megabytes(b) {
        return Math.max(1, Math.round(b / 1000000))
    }

    // Pilot's voice (the Piper voice it ships) is English; speech
    // recognition follows the phone's language.
    readonly property string englishVoiceNote: Qt.locale().name.indexOf("en") === 0 ? ""
        : " " + qsTr("Pilot speaks its answers in English for now.")

    readonly property var capabilities: [
        { name: "text_qa", label: qsTr("Typed questions"),
          description: qsTr("Your questions are sent to Jev and Groq, with personal details replaced.") },
        { name: "voice_cloud", label: qsTr("Spoken questions"),
          description: qsTr("Transcripts of spoken questions are handled like typed ones. Audio never leaves the phone.")
                       + englishVoiceNote },
        { name: "vision", label: qsTr("Camera questions"),
          description: qsTr("A smaller copy of your photo is sent with the question, without its location.") },
        { name: "triage", label: qsTr("Notification sorting"),
          description: qsTr("New notifications, messages and calendar changes are sorted into Pilot events.") },
        { name: "cloud_asr", label: qsTr("Cloud speech recognition"),
          description: qsTr("If the phone can't understand you, the audio is sent to be recognised. Off by default.") },
        { name: "spoken_nudges", label: qsTr("Spoken nudges"),
          description: qsTr("Pilot may speak when something urgent arrives.") + englishVoiceNote },
        { name: "history", label: qsTr("Conversation history"),
          description: qsTr("Your conversations stay on this phone for 30 days, so you can ask Pilot about them later. Nothing extra is sent. Turning this off deletes them.") }
    ]

    function reload() {
        var s = JSON.parse(Pilot.settings())
        if (s.error !== undefined) {
            message = s.error
            return
        }
        settings = s
    }

    // Errors stay on the page; a confirmation is a notice (Silica's
    // transient feedback).
    function report(err, done) {
        message = err
        if (!err.length && done.length)
            Notices.show(done, Notice.Short)
        reload()
    }

    Component.onCompleted: {
        reload()
        memories = JSON.parse(Pilot.memories())
        voiceModelsBytes = Pilot.voiceModelsBytes()
        ready = true
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge * 2

        Column {
            id: column
            width: parent.width

            PageHeader { title: qsTr("Pilot settings") }

            Label {
                objectName: "settingsMessage"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                visible: text.length > 0
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                text: page.message
            }

            SectionHeader { text: qsTr("You") }
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
                onClicked: pageStack.push(Qt.resolvedUrl("OnboardingDialog.qml"), { again: true })
            }

            SectionHeader { text: qsTr("What Pilot remembers") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: page.memories.length === 0
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
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
                                Pilot.forget(memoryItem.modelData.id)
                                page.memories = JSON.parse(Pilot.memories())
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

            SectionHeader { text: qsTr("Cloud use, per capability") }
            Repeater {
                model: page.capabilities
                TextSwitch {
                    id: consentSwitch
                    required property var modelData
                    objectName: "consent_" + consentSwitch.modelData.name
                    text: consentSwitch.modelData.label
                    description: consentSwitch.modelData.description
                    checked: page.settings.consent[consentSwitch.modelData.name] === true
                    onCheckedChanged: {
                        var name = consentSwitch.modelData.name
                        if (!page.ready || checked === (page.settings.consent[name] === true))
                            return
                        page.report(Pilot.setConsent(name, checked), "")
                    }
                }
            }

            SectionHeader { text: qsTr("Service") }
            ComboBox {
                id: backend
                objectName: "backendCombo"
                label: qsTr("Service")
                description: page.settings.backend === "lighthouse"
                             ? qsTr("Every step stays on EU-hosted, EU-operated servers.")
                             : qsTr("Deciding what you asked (Jev) and writing answers (Groq) both run in the United States. Lighthouse keeps every step in the EU.")
                currentIndex: Math.max(0, page.settings.backends.indexOf(page.settings.backend))
                menu: ContextMenu {
                    Repeater {
                        model: page.settings.backends
                        MenuItem {
                            required property string modelData
                            text: modelData === "standard" ? qsTr("Standard (Jev and Groq, US)")
                                : modelData === "lighthouse" ? qsTr("Lighthouse (EU only)")
                                : modelData
                        }
                    }
                }
                onCurrentIndexChanged: {
                    var name = page.settings.backends[currentIndex]
                    if (!page.ready || name === undefined || name === page.settings.backend)
                        return
                    page.report(Pilot.setBackend(name), "")
                }
            }

            SectionHeader { text: qsTr("Your data") }
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
                        left: parent.left; leftMargin: Theme.horizontalPageMargin
                        right: parent.right; rightMargin: Theme.horizontalPageMargin
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
            Item { width: 1; height: Theme.paddingLarge }
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
                        var path = Pilot.defaultExportPath()
                        var err = Pilot.exportTo(path)
                        page.dataMessage = err.length ? err : qsTr("Saved to %1").arg(path)
                    }
                }
                Button {
                    objectName: "wipeButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: qsTr("Delete records")
                    onClicked: remorse.execute(qsTr("Deleting Pilot's records"), function() {
                        var err = Pilot.wipe()
                        page.dataMessage = err
                        if (!err.length)
                            Notices.show(qsTr("Pilot's records deleted"), Notice.Short)
                    })
                }
            }
            // The speech models are downloaded, not installed: removing
            // the app leaves them, so they are removed here.
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: page.voiceModelsBytes > 0
                topPadding: Theme.paddingLarge
                Label {
                    objectName: "voiceModelsLabel"
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    text: qsTr("Downloaded voice models: %1 MB. Removing Pilot does not remove them; remove them here first. Pilot downloads one again the next time you speak to it.").arg(page.megabytes(page.voiceModelsBytes))
                }
                Button {
                    objectName: "removeVoiceModelsButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: qsTr("Remove downloaded voice models")
                    onClicked: remorse.execute(qsTr("Removing voice models"), function() {
                        var err = Pilot.removeVoiceModels()
                        page.dataMessage = err
                        page.voiceModelsBytes = Pilot.voiceModelsBytes()
                        if (!err.length)
                            Notices.show(qsTr("Voice models removed"), Notice.Short)
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
                color: page.dataMessage.length > 0 ? Theme.highlightColor : Theme.secondaryHighlightColor
                text: page.dataMessage.length > 0 ? page.dataMessage
                    : qsTr("Export saves the log of what left this phone to Downloads. Delete removes the log and the conversation.")
            }
        }
        VerticalScrollDecorator {}
    }

    RemorsePopup { id: remorse }
}
