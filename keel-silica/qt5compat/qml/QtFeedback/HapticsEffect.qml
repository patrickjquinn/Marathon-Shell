// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QtFeedback 5.0 HapticsEffect (no-op, see FeedbackEffect.qml).
import QtQml 2.15

FeedbackEffect {
    property real attackIntensity: 0
    property int attackTime: 0
    property real intensity: 1
    property int fadeTime: 0
    property real fadeIntensity: 0
    property int period: -1
    property var actuator: null
    readonly property var availableActuators: []
}
