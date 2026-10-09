// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QtFeedback 5.0 ThemeEffect: `effect`, `supported`, `play()`, `play(effect)`.
// No-op: nothing is played and `supported` is false.
import QtQml 2.15

QtObject {
    // Qt 5 has Undefined = -1; Qt 6.4 rejects negative QML enum values
    // (Keel's floor is 6.4), so Undefined is a positive stand-in here.
    enum Effect {
        Press, Release, PressWeak, ReleaseWeak, PressStrong, ReleaseStrong,
        DragStart, DragDropInZone, DragDropOutOfZone, DragCrossBoundary,
        Appear, Disappear, Move,
        NumberOfEffects,
        Undefined = 65534,
        UserEffect = 65535
    }

    property int effect: 65534 // Undefined
    readonly property bool supported: false

    function play(effectToPlay) {
    }
}
