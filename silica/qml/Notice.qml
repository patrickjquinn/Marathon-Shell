// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Notice: an in-app notification shown over the application's UI. API
// (text, duration with Notice.Short / Notice.Long, anchor with Notice.Center
// / Left / Right / Top / Bottom flags, horizontalOffset, verticalOffset,
// show(), dismiss()) from the Silica public documentation; implementation
// clean-room. The numeric values are Keel's. Notices shows one notice at a
// time with Silica's own private NoticeItem (BSD, qml/private).
import QtQuick
import Sailfish.Silica 1.0

QtObject {
    id: notice

    enum Duration { Short = 3000, Long = 5000 }
    enum Anchor { Center = 0, Left = 1, Right = 2, Top = 4, Bottom = 8 }

    property string text
    property int duration: Notice.Long
    property int anchor: Notice.Bottom
    property real horizontalOffset
    property real verticalOffset
    // Keel: whether the notice is on screen now.
    readonly property bool _shown: Notices._current === notice
    // Keel: made by Notices.show(), destroyed once shown.
    property bool _transient: false

    function show() {
        Notices._show(notice)
    }

    function dismiss() {
        Notices._dismiss(notice)
    }

    Component.onDestruction: Notices._dismiss(notice)
}
