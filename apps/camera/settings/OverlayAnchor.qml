// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica first: on Keel (Qt 6) the first import providing `Screen` wins.
import Sailfish.Silica 1.0
import QtQuick 2.0

Item {
    // Position bottom controls so that they are vertically centered
    // inside the bottom area below the 4:3 aspect ratio viewport
    property int smallMargin: Theme.paddingLarge + Theme.paddingMedium
    property int largeMargin: Math.max(smallMargin, (Screen.height - 4 / 3 * Screen.width - (reallyWideScreen ? Theme.itemSizeLarge : 0)) / 2 - height / 2)
    anchors {
        topMargin: smallMargin
        leftMargin: smallMargin
        rightMargin: isPortrait ? smallMargin : largeMargin
        bottomMargin: isPortrait ? largeMargin : smallMargin
    }
    width: Theme.itemSizeMedium
    height: Theme.itemSizeMedium
}
