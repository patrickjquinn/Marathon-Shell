// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) Label.qml
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: no fade layer on the software scene graph (it runs no shaders); the text is elided there instead, and laid out again when it grows.
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour).

pragma ComponentBehavior: Bound // Modified by Shipwright for Qt 6: ids of outer objects used in inner components
import QtQuick 2.6
import QtQuick as KeelQuick // Modified by Shipwright for Qt 6: GraphicsInfo (newer than this file's QtQuick import)
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below

Private.SilicaText {
    id: root

    property int truncationMode
    property bool _fadeText: width > 0 && truncationMode == TruncationMode.Fade
                             && lineCount == 1
                             && contentWidth > Math.ceil(width)
                             && KeelQuick.GraphicsInfo.api !== KeelQuick.GraphicsInfo.Software // Modified by Shipwright for Qt 6: no shaders on the software scene graph
    property bool _elideText: truncationMode == TruncationMode.Elide
                              || (truncationMode == TruncationMode.Fade && KeelQuick.GraphicsInfo.api === KeelQuick.GraphicsInfo.Software) // Modified by Shipwright for Qt 6: elided where no shader can fade it (tested before lineCount, which eliding changes)
                              || (truncationMode == TruncationMode.Fade && lineCount > 1)

    elide: _elideText ? (horizontalAlignment == Text.AlignLeft
                         ? Text.ElideRight
                         : (horizontalAlignment == Text.AlignRight ? Text.ElideLeft
                                                                   : Text.ElideMiddle))
                      : Text.ElideNone

    color: highlighted ? palette.highlightColor : palette.primaryColor
    font.pixelSize: Theme.fontSizeMedium
    textFormat: _defaultLabelFormat

    // Modified by Shipwright for Qt 6: an elided text (the software stand-in for the fade) is laid
    // out again when its width follows a grown text (PageHeader's description), which Qt 6.4
    // otherwise leaves elided at the old width.
    // Only growth past the widest width already laid out counts, once per text: a
    // wrapped, elided label alternates between two implicit widths as it is laid out,
    // and re-laying it out on every change looped forever on the main thread.
    property real _laidOutImplicitWidth: -1
    onTextChanged: _laidOutImplicitWidth = -1
    onImplicitWidthChanged: {
        if (elide !== Text.ElideNone && implicitWidth > _laidOutImplicitWidth) {
            _laidOutImplicitWidth = implicitWidth
            Qt.callLater(root.forceLayout)
        }
    }
    on_FadeTextChanged: {
        if (_fadeText) {
            layer.enabled = true
            layer.smooth = true
            layer.effect = rampComponent
        } else {
            layer.enabled = false
            layer.effect = null
        }
    }

    Component {
        id: rampComponent

        OpacityRampEffectBase {
            direction: root.horizontalAlignment == Text.AlignRight ? OpacityRamp.RightToLeft // Modified by Shipwright for Qt 6: qualified
                                                              : OpacityRamp.LeftToRight
            source: root
            slope: Math.max(1 + 6 * root.width / KeelSilica.Screen.width,
                            root.width / Math.max(1, 2 * (root.implicitWidth - width)))
            offset: 1 - 1 / slope
        }
    }
}
