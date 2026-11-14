// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Provenance: clean-room from the Sailfish Silica public documentation
// (OpacityRampEffect.direction values). Numeric values follow the comment in
// Silica's BSD OpacityRampEffectBase.qml (LtR 0 .. BothEnds 5), which its
// shader relies on.

import QtQml

QtObject {
    enum Direction { LeftToRight, RightToLeft, TopToBottom, BottomToTop, BothSides, BothEnds }
}
