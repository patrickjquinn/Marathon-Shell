// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot's card layout: a column inside the page margins, directly on the
// ambience. Items placed inside go into the column.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: glass

    default property alias content: column.data
    property alias spacing: column.spacing

    width: parent ? parent.width : 0
    implicitHeight: column.height + 2 * Theme.paddingMedium

    Column {
        id: column
        x: Theme.horizontalPageMargin
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingMedium
    }
}
