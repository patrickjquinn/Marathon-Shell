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

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private

Private.SilicaText {
    id: root

    property int truncationMode
    property bool _fadeText: width > 0 && truncationMode == TruncationMode.Fade
                             && lineCount == 1
                             && contentWidth > Math.ceil(width)
    property bool _elideText: truncationMode == TruncationMode.Elide
                              || (truncationMode == TruncationMode.Fade && lineCount > 1)

    elide: _elideText ? (horizontalAlignment == Text.AlignLeft
                         ? Text.ElideRight
                         : (horizontalAlignment == Text.AlignRight ? Text.ElideLeft
                                                                   : Text.ElideMiddle))
                      : Text.ElideNone

    color: highlighted ? palette.highlightColor : palette.primaryColor
    font.pixelSize: Theme.fontSizeMedium
    textFormat: _defaultLabelFormat

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
            direction: horizontalAlignment == Text.AlignRight ? OpacityRamp.RightToLeft
                                                              : OpacityRamp.LeftToRight
            source: root
            slope: Math.max(1 + 6 * root.width / Screen.width,
                            root.width / Math.max(1, 2 * (root.implicitWidth - width)))
            offset: 1 - 1 / slope
        }
    }
}
