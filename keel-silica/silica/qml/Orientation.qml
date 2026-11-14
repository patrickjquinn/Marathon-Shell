// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Provenance: clean-room from the Sailfish Silica public documentation
// (enumeration names). Numeric values are Keel's own unless noted.

import QtQml

QtObject {
    // Values follow Qt::ScreenOrientation bit flags so masks combine with |.
    enum Orientation {
        None = 0,
        Portrait = 1,
        Landscape = 2,
        PortraitInverted = 4,
        LandscapeInverted = 8,
        PortraitMask = 5,
        LandscapeMask = 10,
        All = 15
    }
}
