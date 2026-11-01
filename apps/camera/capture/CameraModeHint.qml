// SPDX-FileCopyrightText: 2018 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2024 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0

Loader {
    anchors.fill: parent
    // Off until Keel's TouchInteractionHint is fixed: its animation's
    // ScriptAction changes a PauseAnimation duration while the group runs,
    // which restarts the group from inside itself and crashes Qt 6.4
    // (reported to Keel).
    active: false && counter.active
    asynchronous: true
    sourceComponent: Component {
        Item {
            anchors.fill: parent

            InteractionHintLabel {
                text: qsTr("Swipe down to access camera settings")
                anchors.bottom: parent.bottom
                opacity: touchInteractionHint.running ? 1.0 : 0.0
                Behavior on opacity {
                    FadeAnimation {
                        duration: 800
                    }
                }
                textColor: Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)
                backgroundColor: Theme.rgba(Theme.highlightDimmerFromColor(Theme.highlightDimmerColor, Theme.LightOnDark), 0.9)
            }
            TouchInteractionHint {
                id: touchInteractionHint

                direction: TouchInteraction.Down
                alwaysRunToEnd: true
                distance: Theme.itemSizeMedium
                color: Theme.lightPrimaryColor
                onRunningChanged: {
                    if (!running) {
                        counter.increase();
                    }
                }

                Component.onCompleted: restart()
            }
        }
    }
    FirstTimeUseCounter {
        id: counter

        limit: 2
        key: "/sailfish/camera/camera_mode_hint_count"
    }
}
