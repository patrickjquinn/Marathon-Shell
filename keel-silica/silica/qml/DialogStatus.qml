// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Provenance: clean-room from the Sailfish Silica public documentation
// (enumeration names). Numeric values are Keel's own unless noted.

import QtQml

QtObject {
    // Numerically equal to PageStatus, so a Dialog's status compares with both.
    enum Status { Closed, Opening, Opened, Closing }
}
