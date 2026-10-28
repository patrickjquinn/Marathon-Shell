// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Learn Pilot: what it can do, how to reach it, and how it works, in the
// person's words. A section per skill of the getting-started guide
// (GuideCard.qml), each with a way to try it; opened at the one tapped.
// Also the way to the camera and to what Pilot can do in the apps.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0
import "../components"

Page {
    id: page
    objectName: "guidePage"

    // The section to open at: a guide step, or "" for the top.
    property string focusStep: ""
    readonly property var settings: JSON.parse(Pilot.settings())

    // Back on the main page, to try something there.
    function mainPage() {
        var main = pageStack.find(function(p) { return p.objectName === "mainPage" })
        if (main)
            pageStack.pop(main)
        return main
    }

    onStatusChanged: {
        if (status !== PageStatus.Active || focusStep === "")
            return
        var target = column.sectionFor(focusStep)
        if (target)
            flick.contentY = Math.max(0, Math.min(target.y - Theme.paddingLarge, flick.contentHeight - flick.height))
        focusStep = ""
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            function sectionFor(step) {
                for (var i = 0; i < children.length; ++i)
                    if (children[i].step === step)
                        return children[i]
                return null
            }

            PageHeader {
                title: qsTr("Learn Pilot")
                description: qsTr("%1 of %2 tried").arg(Conversation.guideDone).arg(Conversation.guideSteps.length)
            }

            // 1. From anywhere.
            GuideSection {
                step: "gesture"
                title: qsTr("Bring Pilot up from any app")
                body: page.settings.gesture
                      ? qsTr("There's a glowing bar at the bottom of the screen. Touch and hold it. "
                             + "The edges light up and Pilot opens over the app you're in. "
                             + "A swipe up still opens your apps.")
                      : qsTr("Install “Pilot gesture” from Reef. It adds a glowing bar at the bottom of the screen. "
                             + "Touch and hold it to open Pilot over any app.")
                GestureDemo {
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                SectionNote {
                    text: qsTr("To close it, tap the cross or the app behind it, or swipe the field down. "
                               + "The arrow continues the conversation here.")
                }
            }

            // 2. About the screen.
            GuideSection {
                step: "screen"
                title: qsTr("Ask about what's on screen")
                body: qsTr("Over an app, Pilot can see what the app shows. “This” means what's on your screen. "
                           + "Try asking:")
                // Examples to say, not buttons.
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: [qsTr("\u201cSummarise this\u201d"), qsTr("\u201cExplain this simply\u201d"),
                           qsTr("\u201cReply to this\u201d"), qsTr("\u201cWhat are the key points?\u201d")].join("   ")
                    color: Theme.highlightColor
                }
                SectionNote {
                    text: qsTr("Pilot only looks when you open it, and only at the app on top. "
                               + "If it reads a web page, the request is listed in “What left this phone”.")
                }
            }

            // 3. Speaking.
            GuideSection {
                step: "voice"
                title: qsTr("Talk to Pilot")
                body: qsTr("Tap the orb and say what you want. Pilot stops listening when you pause. "
                           + "Your speech is turned into text on this phone, and only the text is sent.")
                Button {
                    objectName: "guideTryVoice"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Try it now")
                    enabled: !Pilot.offline
                    onClicked: {
                        var main = page.mainPage()
                        if (main)
                            main.listen()
                    }
                }
            }

            // 4. Doing things.
            GuideSection {
                step: "action"
                title: qsTr("Let Pilot do things for you")
                body: qsTr("Timers, alarms, reminders and your calendar work on the phone, straight away. "
                           + "Pilot can also find, write, install and send in apps that support it. "
                           + "It can do several steps across apps.")
                SectionNote {
                    text: qsTr("Before Pilot sends, buys, installs or deletes anything, it shows you each step. "
                               + "Nothing happens until you tap Allow.")
                }
                Button {
                    objectName: "guideCapabilities"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("What Pilot can do")
                    onClicked: pageStack.push(Qt.resolvedUrl("CapabilitiesPage.qml"))
                }
            }

            // 5. Explanations.
            GuideSection {
                step: "how"
                title: qsTr("See how Pilot answered")
                body: qsTr("Under an answer, tap “How Pilot answered”. It lists what Pilot looked at: your screen, "
                           + "the web or your apps. It also says how many personal details were hidden before sending. "
                           + "Pages it used are linked under the answer.")
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("What left this phone")
                    onClicked: pageStack.push(Qt.resolvedUrl("EgressLogPage.qml"))
                }
            }

            // And: showing Pilot something, and what it remembers.
            GuideSection {
                title: qsTr("Show Pilot something")
                body: qsTr("Take a photo of a plant, a sign or a menu, and ask about it. "
                           + "Pilot sends a smaller copy without its location.")
                Button {
                    objectName: "guideCamera"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Look with the camera")
                    onClicked: {
                        var main = page.mainPage()
                        if (main)
                            main.openCamera("")
                    }
                }
            }
            GuideSection {
                title: qsTr("Tell Pilot what to remember")
                body: qsTr("Say “remember that my partner loves orchids” and Pilot keeps it on this phone. "
                           + "Say “forget” to remove it. Settings lists everything Pilot remembers.")
            }
        }
        VerticalScrollDecorator {}
    }

    component GuideSection: Column {
        id: section
        property string step: ""
        property string title
        property string body
        readonly property bool done: step.length > 0 && Conversation.guide.indexOf(step) >= 0
        default property alias content: extra.data

        x: Theme.horizontalPageMargin
        width: page.width - 2 * x
        spacing: Theme.paddingMedium

        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: section.done ? qsTr("%1 · tried").arg(section.title) : section.title
            font.pixelSize: Theme.fontSizeLarge
            font.family: Theme.fontFamilyHeading
            color: Theme.highlightColor
        }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: section.body
            color: Theme.highlightColor
        }
        Column {
            id: extra
            width: parent.width
            spacing: Theme.paddingMedium
        }
    }

    component SectionNote: Label {
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondaryHighlightColor
    }
}
