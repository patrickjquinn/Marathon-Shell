// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// GestureHintAnimation (private): a nudge back and forth that hints at a
// swipe, used as a property value source (`GestureHintAnimation on x`) by
// Silica's BSD private/SwipeItem.qml. Silica's own file is not open (no BSD
// header in sailfishsilica-qt5 1.2.156); Keel's clean-room stand-in.
import QtQuick
import Sailfish.Silica 1.0

SequentialAnimation {
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: Theme.paddingLarge; duration: 300; easing.type: Easing.OutQuad }
    NumberAnimation { to: 0; duration: 300; easing.type: Easing.InQuad }
    PauseAnimation { duration: 400 }
}
