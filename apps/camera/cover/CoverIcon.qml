// SPDX-FileCopyrightText: 2013 - 2020 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0

Image {
    property url icon

    fillMode: Image.PreserveAspectFit
    source: icon.toString().length ? icon + "?" + (Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)) : ""

    scale: 0.75
}
