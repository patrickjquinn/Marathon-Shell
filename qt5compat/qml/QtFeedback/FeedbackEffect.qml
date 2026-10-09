// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Common part of HapticsEffect and FileEffect (QtFeedback's FeedbackEffect):
// start() (or `running = true`) moves to Running and back to Stopped after
// `duration` ms (never for Feedback.Infinite or a negative duration), pause() (or `paused = true`) to
// Paused, stop() to Stopped. No device output.
import QtQml 2.15

QtObject {
    id: effect

    // Feedback.State: Stopped 0, Paused 1, Running 2, Loading 3.
    readonly property int state: __state
    property bool running: false
    property bool paused: false
    property int duration: 250

    signal error(int error)

    function start() {
        __setState(2)
        if (!__infinite)
            __timer.restart()
    }
    function stop() {
        __timer.stop()
        __setState(0)
    }
    function pause() {
        __timer.stop()
        if (__state === 2)
            __setState(1)
    }

    property int __state: 0
    readonly property bool __infinite: duration < 0 || duration === Feedback.Infinite
    property bool __syncing: false
    property Timer __timer: Timer {
        interval: Math.max(effect.duration, 0)
        repeat: false
        onTriggered: effect.__setState(0)
    }

    function __setState(s) {
        __syncing = true
        __state = s
        running = s === 2
        paused = s === 1
        __syncing = false
    }

    onRunningChanged: {
        if (__syncing)
            return
        if (running)
            start()
        else
            stop()
    }
    onPausedChanged: {
        if (__syncing)
            return
        if (paused)
            pause()
        else if (__state === 1)
            start()
    }
}
