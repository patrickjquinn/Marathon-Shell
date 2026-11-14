// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Provenance: clean-room from the Sailfish Silica public documentation
// (enumeration names). Numeric values are Keel's own unless noted.

import QtQml

QtObject {
    // Names as Silica's BSD QML (Page, PageStack, Dialog) uses them.
    enum Navigation { NoNavigation, Back, Forward }
    enum Direction { NoDirection, Left, Right, Up, Down }
    enum Style { Horizontal = 0, Vertical = 1 }
}
