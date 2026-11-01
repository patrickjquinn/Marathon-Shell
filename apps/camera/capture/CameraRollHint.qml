// SPDX-FileCopyrightText: 2018 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2024 - 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica first: on Keel (Qt 6) the first import providing `Screen` wins.
import Sailfish.Silica 1.0
import QtQuick 2.0

Loader {
    anchors.fill: parent
    // Off until Keel's TouchInteractionHint is fixed: its animation's
    // ScriptAction changes a PauseAnimation duration while the group runs,
    // which restarts the group from inside itself and crashes Qt 6.4
    // (reported to Keel).
    active: false && counter.active
    sourceComponent: Component {
        Item {
            Connections {
                target: captureView
                function onCaptured() {
                    touchInteractionHint.restart();
                    counter.increase();
                }
            }

            anchors.fill: parent
            InteractionHintLabel {
                text: qsTr("Swipe right to access the Camera Roll")
                anchors.bottom: parent.bottom
                opacity: touchInteractionHint.running ? 1.0 : 0.0
                Behavior on opacity {
                    FadeAnimation {
                        duration: 1000
                    }
                }
                textColor: Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)
                backgroundColor: Theme.rgba(Theme.highlightDimmerFromColor(Theme.highlightDimmerColor, Theme.LightOnDark), 0.9)
            }
            TouchInteractionHint {
                id: touchInteractionHint

                color: Theme.lightPrimaryColor
                startX: parent.width / 2 - width / 2 + (page.isLandscape ? Screen.width / 3 : 0)
                direction: TouchInteraction.Right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: page.isPortrait ? Screen.width / 3 : 0
            }
        }
    }
    FirstTimeUseCounter {
        id: counter

        limit: 3
        defaultValue: 1 // display hint twice for existing users
        key: "/sailfish/camera/camera_roll_hint_count"
    }
}
