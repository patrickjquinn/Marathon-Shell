// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Keel.Ambience reads keel-shell's forwarded dconf keys and KEEL_THEME_
// overrides (environment set by tests/CMakeLists.txt), and applies runtime
// updates in keel-shell's AmbienceChanged format.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Keel 1.0

TestCase {
    name: "AmbienceEnv"

    function test_forwarded_environment() {
        compare(Theme.colorScheme, Theme.DarkOnLight)
        verify(Qt.colorEqual(Theme.primaryColor, "black"))
        // Opaque, as in Sailfish's light ambience files.
        verify(Qt.colorEqual(Theme.secondaryColor, "#454545"))
        compare(Theme.pixelRatio, 2.0)
        compare(Theme.paddingLarge, 48)
        compare(Ambience.source, "defaults + keel-shell environment + KEEL_THEME_ overrides")
    }

    function test_override() {
        verify(Qt.colorEqual(Theme.errorColor, "#ff00ff"))
    }

    function test_highlight_adjusted_for_scheme() {
        // #0055aa is dark enough for a light ambience and is kept.
        verify(Qt.colorEqual(Theme.highlightColor, "#0055aa"))
        // A little darker, as Sailfish's light ambiences have it (airy:
        // #004c99 -> #003d76).
        verify(Theme.secondaryHighlightColor.hslLightness < Theme.highlightColor.hslLightness)
    }

    function test_runtime_update() {
        var spy = Qt.createQmlObject("import QtTest 1.0; SignalSpy { signalName: 'ambienceChanged' }", this)
        spy.target = Ambience
        Ambience.applyForwarded("/desktop/jolla/theme/color/highlight=#ff8800\n/desktop/jolla/theme/color_scheme=lightondark\n")
        compare(spy.count, 1)
        compare(Theme.colorScheme, Theme.LightOnDark)
        verify(Qt.colorEqual(Theme.highlightColor, "#ff8800"))
        verify(Qt.colorEqual(Theme.primaryColor, "white"))
        // Overrides still win.
        verify(Qt.colorEqual(Theme.errorColor, "#ff00ff"))
        compare(Ambience.source, "defaults + keel-shell environment + keel-shell D-Bus + KEEL_THEME_ overrides")
        Ambience.applyForwarded("")
        compare(Theme.colorScheme, Theme.DarkOnLight)
    }
}
