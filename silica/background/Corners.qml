// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Corners (Sailfish.Silica.Background): flags for ColorBackground's
// `roundedCorners`. Names from Silica's BSD QML (RemorseBase, Scrollbar,
// BannerBackground); values are Keel's. Silica's Background module is not
// open (its QML has proprietary headers); this module is Keel's clean-room
// stand-in for the two names the BSD QML uses.
import QtQml

QtObject {
    enum Corner { None = 0, TopLeft = 1, TopRight = 2, BottomLeft = 4, BottomRight = 8, All = 15 }
}
