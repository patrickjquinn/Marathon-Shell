// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TouchInteraction enums for TouchInteractionHint (Silica public
// documentation: Left, Up, Right, Down; Swipe, EdgeSwipe, Pull).
// Clean-room; the numeric values are Keel's.
import QtQml

QtObject {
    enum Direction { Left, Up, Right, Down }
    enum Mode { Swipe, EdgeSwipe, Pull }
}
