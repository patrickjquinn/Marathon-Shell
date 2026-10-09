// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) Slider.qml

import QtQuick 2.4
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0

SliderBase {
    id: slider

    property color backgroundGlowColor: slider.colorScheme === Theme.DarkOnLight ? palette.highlightDimmerColor
                                                                                 : "transparent"

    readonly property real _glassItemPadding: Theme.paddingMedium

    // compensate the existence of glow effect on light ambiences
    _highlightPadding: (slider.colorScheme === Theme.LightOnDark ? 1 : 2) * _glassItemPadding

    _highlightItem: highlight
    _backgroundItem: background
    _progressBarItem: progressBar

    GlassItem {
        id: background

        // extra painting margins (Theme.paddingMedium on both sides) are needed,
        // because glass item doesn't visibly paint across the full width of the item
        x: slider.leftMargin - _glassItemPadding
        width: slider._grooveWidth + 2*_glassItemPadding
        y: slider._extraPadding + _backgroundTopPadding
        height: (slider.colorScheme === Theme.DarkOnLight ? 1.0 : 0.5) * Theme.itemSizeExtraSmall

        dimmed: true
        radius: slider.colorScheme === Theme.DarkOnLight ? 0.06 : 0.05
        falloffRadius: slider.colorScheme === Theme.DarkOnLight ? 0.09 : 0.05
        ratio: 0.0
        color: slider.highlighted ? slider.secondaryHighlightColor : slider.backgroundColor
    }

    GlassItem {
        id: progressBar

        x: background.x
        anchors.verticalCenter: background.verticalCenter
        width: slider._progressBarWidth
        height: background.height
        visible: sliderValue > minimumValue
        dimmed: false
        radius: slider.colorScheme === Theme.DarkOnLight ? 0.05 : 0.04
        falloffRadius: slider.colorScheme === Theme.DarkOnLight ? 0.14 : 0.10
        ratio: 0.0
        color: slider.highlighted ? slider.highlightColor : slider.color
        backgroundColor: slider.backgroundGlowColor
    }

    GlassItem {
        id: highlight

        x: slider._highlightX
        width: Theme.itemSizeMedium
        height: Theme.itemSizeMedium
        radius: 0.17
        falloffRadius: 0.17
        anchors.verticalCenter: background.verticalCenter
        visible: handleVisible
        color: slider.highlighted ? slider.highlightColor : slider.color
        backgroundColor: slider.backgroundGlowColor
    }
}
