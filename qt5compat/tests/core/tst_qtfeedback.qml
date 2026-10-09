// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QtFeedback 5.0 as counter, yubikey, foilauth and wordle use it (Buzz.qml:
// `ThemeEffect { effect: ThemeEffect.Press }`, then `play()`), plus the
// HapticsEffect / FileEffect state machine.
import QtQuick 2.0
import QtTest 1.0
import QtFeedback 5.0

Item {
    ThemeEffect { id: buzz; effect: ThemeEffect.Press }
    HapticsEffect { id: rumble; duration: 50; intensity: 0.5 }
    HapticsEffect { id: endless; duration: Feedback.Infinite }
    FileEffect { id: file; source: "file:///nonexistent.ivt" }
    Loader { id: loader; sourceComponent: Component { ThemeEffect { effect: ThemeEffect.PressWeak } } }

    SignalSpy { id: stateSpy; target: rumble; signalName: "stateChanged" }

    TestCase {
        name: "QtFeedback"

        function test_theme_effect() {
            compare(buzz.effect, ThemeEffect.Press)
            compare(ThemeEffect.Press, 0)
            compare(ThemeEffect.Move, 12)
            verify(ThemeEffect.Undefined !== undefined)
            compare(buzz.supported, false)
            buzz.play()
            buzz.play(ThemeEffect.Release)
            loader.item.play()
            compare(loader.item.effect, ThemeEffect.PressWeak)
        }
        function test_haptics_runs_and_stops() {
            compare(rumble.state, Feedback.Stopped)
            rumble.start()
            compare(rumble.state, Feedback.Running)
            verify(rumble.running)
            tryCompare(rumble, "state", Feedback.Stopped, 1000)
            verify(!rumble.running)
        }
        function test_running_property() {
            rumble.running = true
            compare(rumble.state, Feedback.Running)
            rumble.paused = true
            compare(rumble.state, Feedback.Paused)
            verify(!rumble.running)
            rumble.stop()
            compare(rumble.state, Feedback.Stopped)
            verify(!rumble.paused)
        }
        function test_infinite() {
            verify(Feedback.Infinite !== undefined)
            endless.start()
            tryCompare(endless, "state", Feedback.Running)
            // Run a finite effect alongside: once it has finished on its own,
            // more than its duration has passed and the endless one must
            // still be running.
            rumble.start()
            compare(rumble.state, Feedback.Running)
            tryCompare(rumble, "state", Feedback.Stopped, 5000)
            compare(endless.state, Feedback.Running)
            endless.stop()
            compare(endless.state, Feedback.Stopped)
        }
        function test_file_effect() {
            file.load()
            verify(!file.loaded)
            compare(file.supportedMimeTypes.length, 0)
        }
    }
}
