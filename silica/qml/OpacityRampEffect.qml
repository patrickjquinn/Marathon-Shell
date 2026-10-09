// SPDX-FileCopyrightText: 2014 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2014 Jolla Ltd.
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) OpacityRampEffect.qml
// Modified by Shipwright for Qt 6: no effect on the software scene graph (it runs no shaders): the source is shown unfaded there.

import QtQuick 2.0
import QtQuick as KeelQuick // Modified by Shipwright for Qt 6: GraphicsInfo (newer than this file's QtQuick import)
import Sailfish.Silica.private 1.0

OpacityRampEffectBase {
    id: root

    // source item will be replaced by this effect item
    property Item sourceItem

    /*override*/ property bool enabled: true

    anchors.fill: sourceItem
    // Modified by Shipwright for Qt 6: the software scene graph runs no shaders; show the source unfaded there
    readonly property bool _keelShaders: KeelQuick.GraphicsInfo.api !== KeelQuick.GraphicsInfo.Software
    visible: enabled && sourceItem && sourceItem.visible && _keelShaders
    source: effectsource

    ShaderEffectSource {
        id: effectsource

        hideSource: root.enabled && root._keelShaders // Modified by Shipwright for Qt 6
        smooth: true
        sourceItem: root.enabled ? root.sourceItem : null
    }
}
