// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot's card surface: a soft glass panel inset by the page margins,
// tinted by the ambience, with a hairline edge. `accent` warms it with the
// highlight colour (something running, something that needs you). Items
// placed inside go into a column with the card's padding.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: glass

    default property alias content: column.data
    property bool accent: false
    property real padding: Theme.paddingLarge
    property alias spacing: column.spacing

    width: parent ? parent.width : 0
    implicitHeight: column.height + 2 * padding

    Rectangle {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: parent.height
        radius: Theme.paddingLarge
        color: glass.accent ? Theme.rgba(Theme.highlightBackgroundColor, 0.16)
                            : Theme.rgba(Theme.primaryColor, 0.06)
        border.width: 1
        border.color: glass.accent ? Theme.rgba(Theme.highlightColor, 0.28)
                                   : Theme.rgba(Theme.primaryColor, 0.10)
    }

    Column {
        id: column
        x: Theme.horizontalPageMargin + glass.padding
        y: glass.padding
        width: parent.width - 2 * (Theme.horizontalPageMargin + glass.padding)
        spacing: Theme.paddingMedium
    }
}
