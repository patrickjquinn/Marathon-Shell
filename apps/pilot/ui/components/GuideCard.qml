// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Getting to know Pilot, on its home until every skill has been tried or
// the person puts it away: five things worth knowing, each ticked when the
// person does it (Conversation.markGuide), not when they read about it. A
// row opens its lesson (GuidePage.qml); the last row, everything Pilot
// can do in the person's apps (CapabilitiesPage.qml).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0

Glass {
    id: card
    objectName: "guideCard"

    signal openLesson(string step)
    signal openCapabilities()

    readonly property var lessons: [
        { step: "gesture", title: qsTr("Bring Pilot up from any app"),
          hint: qsTr("Touch and hold the glowing bar at the bottom") },
        { step: "screen", title: qsTr("Ask about what's on screen"),
          hint: qsTr("“Summarise this” over a page or a message") },
        { step: "voice", title: qsTr("Talk to Pilot"),
          hint: qsTr("Tap the orb and speak") },
        { step: "action", title: qsTr("Let Pilot do things for you"),
          hint: qsTr("Timers, reminders, and actions in your apps") },
        { step: "how", title: qsTr("See how Pilot answered"),
          hint: qsTr("Under an answer: what it looked at, and what left the phone") }
    ]

    accent: true

    Item {
        width: parent.width
        height: Math.max(heading.height, hide.height)
        Label {
            id: heading
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - hide.width - Theme.paddingMedium
            wrapMode: Text.Wrap
            text: qsTr("Get to know Pilot · %1 of %2").arg(Conversation.guideDone).arg(card.lessons.length)
            font.family: Theme.fontFamilyHeading
            color: Theme.highlightColor
        }
        IconButton {
            id: hide
            objectName: "guideHide"
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: Theme.itemSizeSmall
            height: Theme.itemSizeSmall
            icon.source: "image://theme/icon-m-clear"
            onClicked: Conversation.markGuide("hidden")
        }
    }

    Repeater {
        model: card.lessons
        delegate: BackgroundItem {
            id: lesson
            required property var modelData
            readonly property bool done: Conversation.guide.indexOf(lesson.modelData.step) >= 0
            width: parent ? parent.width : 0
            height: Math.max(Theme.itemSizeSmall, texts.height + Theme.paddingMedium)
            highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, 0.25)
            onClicked: card.openLesson(lesson.modelData.step)
            // Done: Silica's ringed tick; to do: the ring alone.
            Item {
                id: mark
                anchors.verticalCenter: parent.verticalCenter
                width: tick.width
                height: tick.height
                Icon {
                    id: tick
                    source: "image://theme/icon-s-checkmark"
                    color: Theme.highlightColor
                    opacity: lesson.done ? 1 : 0
                }
                Rectangle {
                    visible: !lesson.done
                    anchors.centerIn: parent
                    width: tick.width * 0.84
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(2, Theme.paddingSmall / 3)
                    border.color: Theme.rgba(Theme.highlightColor, 0.6)
                }
            }
            Column {
                id: texts
                // Clear of the arrow by the same gap as the tick, however
                // the lines wrap.
                anchors { left: mark.right; leftMargin: Theme.paddingMedium; right: arrow.left; rightMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: lesson.modelData.title
                    font.pixelSize: Theme.fontSizeSmall
                    color: lesson.highlighted || !lesson.done ? Theme.highlightColor : Theme.secondaryHighlightColor
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: lesson.modelData.hint
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                }
            }
            Icon {
                id: arrow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                source: "image://theme/icon-m-right"
                color: Theme.highlightColor
            }
        }
    }

    BackgroundItem {
        objectName: "guideCapabilities"
        width: parent.width
        height: Theme.itemSizeSmall
        highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, 0.25)
        onClicked: card.openCapabilities()
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Everything Pilot can do in your apps")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.highlightColor
        }
    }
}
