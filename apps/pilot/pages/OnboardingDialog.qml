// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// First run, as Silica does a sequence: four dialogs, each accepted with
// the forward gesture (or the header) and backed out of with the back
// one. Hello and what to call you; what Pilot can do; how to bring it up
// from anywhere (holding the bar at the bottom); and where your data is
// (spec section 10, "Consent"). "Use Pilot" turns on typed questions, and
// spoken ones where pilotd can listen unless switched off. Pilot answers on
// the phone, so there is no cloud to keep it from. Backing out of the first
// leaves the choice for later. Shown again from Settings ("Show the
// introduction"), where the choices are already made and the last step
// returns there.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Pilot 1.0
import "../components"

Dialog {
    id: first
    objectName: "onboardingDialog"

    // Shown again from Settings: the choices are already made.
    property bool again: false
    readonly property var settings: JSON.parse(Pilot.settings())
    // The page the sequence returns to: the one under the first step.
    property Item returnTo: null
    // Answer spoken questions too (the last step's switch).
    property bool spoken: true

    onStatusChanged: if (status === PageStatus.Active && !returnTo)
        returnTo = pageStack.previousPage(first)

    acceptDestination: abilitiesStep
    onAccepted: {
        var name = nameField.text.trim();
        if (name !== (settings.name || ""))
            Pilot.setName(name);
    }

    // Accepted at the end of the sequence: typed questions on, and spoken
    // ones as switched.
    function decide() {
        if (!again) {
            Pilot.setConsent("text_qa", true);
            if (Conversation.voiceAvailable)
                Pilot.setConsent("voice_cloud", spoken);
        }
    }

    // 1. Hello, and your name.
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: helloColumn.height + Theme.paddingLarge
        Column {
            id: helloColumn
            width: parent.width
            spacing: Theme.paddingLarge
            DialogHeader {
                acceptText: qsTr("Next")
                cancelText: first.again ? qsTr("Close") : qsTr("Later")
            }
            Orb {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.itemSizeHuge * 1.4
                height: width
                mode: "idle"
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Hi, I'm Pilot")
                font.pixelSize: Theme.fontSizeHuge
                font.family: Theme.fontFamilyHeading
                color: Theme.primaryColor
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Conversation.voiceAvailable ? qsTr("Your assistant on this phone: ask, talk, or let me do things in your apps.") : qsTr("Your assistant on this phone: ask, or let me do things in your apps.")
                color: Theme.secondaryColor
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("What should I call you?")
                placeholderText: qsTr("Your name (optional)")
                text: first.settings.name || ""
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: first.accept()
            }
        }
        VerticalScrollDecorator {}
    }

    // 2. What Pilot can do.
    Component {
        id: abilitiesStep
        Dialog {
            objectName: "onboardingAbilities"
            acceptDestination: bringUpStep
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: abilitiesColumn.height + Theme.paddingLarge
                Column {
                    id: abilitiesColumn
                    width: parent.width
                    spacing: Theme.paddingMedium
                    DialogHeader {
                        title: qsTr("Things to try")
                        acceptText: qsTr("Next")
                        cancelText: qsTr("Back")
                    }
                    Repeater {
                        model: [
                            {
                                icon: "image://theme/icon-m-timer",
                                say: qsTr("“Timer for 10 minutes”"),
                                what: qsTr("Timers, alarms and reminders, right away, on the phone")
                            },
                            {
                                icon: "image://theme/icon-m-website",
                                say: qsTr("“Who won the hurling?”"),
                                what: qsTr("Answers from today's web, with the sources")
                            },
                            {
                                icon: "image://theme/icon-m-note",
                                say: qsTr("“Remember that my partner loves orchids”"),
                                what: qsTr("I keep what you tell me, on this phone, and use it")
                            },
                            {
                                icon: "image://theme/icon-m-search-on-page",
                                say: qsTr("“Summarise this”"),
                                what: qsTr("Over a page or an e-mail: I see what you see")
                            },
                            {
                                icon: "image://theme/icon-m-cloud-download",
                                say: qsTr("“Find a notes app in Reef and install it”"),
                                what: qsTr("I act in your apps, and ask before I send, buy or delete")
                            }
                        ]
                        delegate: Row {
                            id: ability
                            required property var modelData
                            x: Theme.horizontalPageMargin
                            width: abilitiesColumn.width - 2 * x
                            spacing: Theme.paddingLarge
                            Icon {
                                id: abilityIcon
                                anchors.verticalCenter: parent.verticalCenter
                                source: ability.modelData.icon
                                color: Theme.primaryColor
                            }
                            Column {
                                width: parent.width - abilityIcon.width - Theme.paddingLarge
                                Label {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: ability.modelData.say
                                    color: Theme.primaryColor
                                }
                                Label {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: ability.modelData.what
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.secondaryColor
                                }
                            }
                        }
                    }
                }
                VerticalScrollDecorator {}
            }
        }
    }

    // 3. Bringing Pilot up from anywhere.
    Component {
        id: bringUpStep
        Dialog {
            objectName: "onboardingGesture"
            acceptDestination: privacyStep
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: bringUpColumn.height + Theme.paddingLarge
                Column {
                    id: bringUpColumn
                    width: parent.width
                    spacing: Theme.paddingLarge
                    DialogHeader {
                        title: qsTr("Bring me up from anywhere")
                        acceptText: qsTr("Next")
                        cancelText: qsTr("Back")
                    }
                    GestureDemo {
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Touch and hold the bar at the bottom of the screen, in any app. A swipe up still goes home.")
                        color: Theme.primaryColor
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        text: Conversation.voiceAvailable ? qsTr("Over an app, I can see what it shows, so you can say “this”. You can also tap the mic.") : qsTr("Over an app, I can see what it shows, so you can say “this”.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }
                }
                VerticalScrollDecorator {}
            }
        }
    }

    // 4. Your data, and the choice.
    Component {
        id: privacyStep
        Dialog {
            id: last
            objectName: "onboardingPrivacy"
            acceptDestination: first.returnTo
            acceptDestinationAction: PageStackAction.Pop
            onAccepted: first.decide()
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: privacyColumn.height + Theme.paddingLarge
                Column {
                    id: privacyColumn
                    width: parent.width
                    spacing: Theme.paddingMedium
                    DialogHeader {
                        title: qsTr("Your data")
                        acceptText: first.again ? qsTr("Done") : qsTr("Use Pilot")
                        cancelText: qsTr("Back")
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        color: Theme.primaryColor
                        text: qsTr("Timers, alarms, reminders, music and your calendar are handled on this phone.")
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        color: Theme.primaryColor
                        text: qsTr("Other questions are answered on this phone too, with what I remember about you when it helps. " + "Your questions, my answers and what I remember stay here.")
                    }
                    ModelCard {}
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        text: qsTr("To answer from the web I search DuckDuckGo and read the pages from this phone; " + "names, numbers and addresses are replaced first. " + "Settings lists every request under “What left this phone”.")
                    }
                    TextSwitch {
                        objectName: "spokenSwitch"
                        visible: !first.again && Conversation.voiceAvailable
                        checked: first.spoken
                        text: qsTr("Answer spoken questions too")
                        description: qsTr("Your speech is turned into text on this phone. " + "Only the text is sent, never the audio.") +
                        // Pilot's voice is English; recognition
                        // follows the phone's language.
                        (Qt.locale().name.indexOf("en") === 0 ? "" : " " + qsTr("Pilot speaks its answers in English for now."))
                        onCheckedChanged: first.spoken = checked
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        text: qsTr("Camera and notification features are off until you turn them on in Settings.")
                    }
                }
                VerticalScrollDecorator {}
            }
        }
    }
}
