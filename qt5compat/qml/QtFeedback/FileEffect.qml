// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QtFeedback 5.0 FileEffect (no-op, see FeedbackEffect.qml). Nothing is ever
// loaded: `loaded` stays false and `supportedMimeTypes` is empty.
import QtQml 2.15

FeedbackEffect {
    property url source
    readonly property bool loaded: false
    readonly property var supportedMimeTypes: []

    function load() {
    }
    function unload() {
    }
}
