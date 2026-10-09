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

import QtQuick 2.0
import Sailfish.Silica 1.0

SilicaFlickable {
    id: panel

    property bool open
    readonly property bool expanded: open || horizontalAnimation.running || verticalAnimation.running
    readonly property bool moving: horizontalAnimation.running || verticalAnimation.running || mouseArea.drag.active
    property int dock: Dock.Bottom
    property bool modal
    property int animationDuration: 500
    property bool _immediate

    function _visibleSize() {
        if (_managedDock == Dock.Left) {
            return panel.x + panel.width - contentX
        } else if (_managedDock == Dock.Top)  {
            return panel.y + panel.height - contentY
        } else if (_managedDock == Dock.Right && panel.parent) {
            return panel.parent.width - panel.x + contentX
        } else if (_managedDock == Dock.Bottom && panel.parent) {
            return panel.parent.height - panel.y + contentY
        } else {
            return 0
        }
    }

    readonly property real visibleSize: _visibleSize()

    property real _lastPos
    property real _direction
    default property alias _data: mouseArea.data

    property int _managedDock: dock
    property bool _isVertical: _managedDock == Dock.Top || _managedDock == Dock.Bottom
    property real _threshold: Math.min((_isVertical ? height / 3 : width / 3), Theme.dp(90))
    property bool _initialized
    property bool _wasOpen

    property Component background: PanelBackground {
        position: dock
    }

    visible: expanded

    function show(immediate) {
        _initialized = true
        _immediate = !!immediate
        open = true
        _immediate = false
    }

    function hide(immediate) {
        _immediate = !!immediate
        open = false
        _immediate = false
    }

    Component.onCompleted: {
        if (__silica_applicationwindow_instance && parent === __silica_applicationwindow_instance.contentItem) {
            // The panel is most probably a direct child of ApplicationWindow and should not be
            // parented on a resizing item, i.e. contentItem, but a non-resizing (but still
            // orientation aware) item instead, i.e. _rotatingItem.
            parent = __silica_applicationwindow_instance._rotatingItem
        }

        // before allowing opening wait for content item's
        // (e.g. column's) async height changes to kick in
        delayedInitialization.restart()
    }

    Timer {
        id: delayedInitialization

        interval: 16
        onTriggered: _initialized = true
    }

    onDockChanged: {
        _immediate = true
        _managedDock = dock
        _immediate = false
    }

    InverseMouseArea {
        anchors.fill: parent
        enabled: open && modal
        stealPress: true
        onPressedOutside: open = false
    }

    Binding {
        when: open && modal
        target: __silica_applicationwindow_instance
        property: "_dimScreen"
        value: open
    }

    // Effect to eliminate the opacity applied by application window dimming
    layer.enabled: modal && expanded && __silica_applicationwindow_instance._dimmingActive
    layer.smooth: true
    layer.effect: ShaderEffect {
        fragmentShader: "
            uniform sampler2D source;
            varying highp vec2 qt_TexCoord0;
            void main(void)
            {
                highp vec4 pixelColor = texture2D(source, qt_TexCoord0);
                gl_FragColor = pixelColor;
            }
            "
    }

    // State transitions would be more appropriate, but the Qt Quick Transition animation
    // jumps to the end position before animating from beginning to the end, which causes
    // various issues when the docked panel reduces page height and flickable viewport.
    onTargetXChanged: {
        if ((_wasOpen !== open || verticalAnimation.running) && _initialized && !_immediate) {
            horizontalBehavior.enabled = true
        }
        x = targetX
        horizontalBehavior.enabled = false
        _wasOpen = open
    }

    onTargetYChanged: {
        if ((_wasOpen !== open || horizontalAnimation.running) && _initialized && !_immediate) {
            verticalBehavior.enabled = true
        }
        y = targetY
        verticalBehavior.enabled = false
        _wasOpen = open
    }

    property real targetX: {
        if (_managedDock == Dock.Left) {
            return -panel.width
        } else if (_managedDock == Dock.Right && panel.parent) {
            return panel.parent.width
        } else {
            return 0
        }
    }

    property real targetY: {
        if (_managedDock == Dock.Top) {
            return -panel.height
        } else if (_managedDock == Dock.Bottom && panel.parent) {
            return panel.parent.height
        } else {
            return 0
        }
    }

    states: State {
        name: "open"
        when: open && _initialized
        PropertyChanges {
            target: panel
            targetX: {
                if (_managedDock == Dock.Left) {
                    return 0
                } else if (_managedDock == Dock.Right && panel.parent) {
                    return panel.parent.width - panel.width
                } else {
                    return 0
                }
            }
            targetY: {
                if (_managedDock == Dock.Top) {
                    return 0
                } else if (_managedDock == Dock.Bottom && panel.parent) {
                    return panel.parent.height - panel.height
                } else {
                    return 0
                }
            }
        }
    }

    Behavior on x {
        id: horizontalBehavior

        enabled: false
        NumberAnimation {
            id: horizontalAnimation
            duration: animationDuration; easing.type: Easing.OutQuad
        }
    }

    Behavior on y {
        id: verticalBehavior

        enabled: false
        NumberAnimation {
            id: verticalAnimation
            duration: animationDuration; easing.type: Easing.OutQuad
        }
    }

    Loader {
        sourceComponent: background
        anchors.fill: mouseArea
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        drag {
            target: panel
            minimumX: !panel._isVertical ? mouseArea.drag.maximumX - panel.width : 0
            maximumX: _managedDock == Dock.Right && panel.parent ? panel.parent.width : 0
            minimumY: panel._isVertical ? mouseArea.drag.maximumY - panel.height : 0
            maximumY: _managedDock == Dock.Bottom && panel.parent ? panel.parent.height : 0
            axis: panel._isVertical ? Drag.YAxis : Drag.XAxis
            filterChildren: true
            onActiveChanged: {
                if (!drag.active) {
                    if ((panel._managedDock == Dock.Left          && panel.x < -panel._threshold && panel._direction <= 0)
                            || (panel._managedDock == Dock.Top    && panel.y < -panel._threshold && panel._direction <= 0)
                            || (panel._managedDock == Dock.Right  && panel.x - drag.minimumX >  panel._threshold && panel._direction >= 0)
                            || (panel._managedDock == Dock.Bottom && panel.y - drag.minimumY >  panel._threshold && panel._direction >= 0)) {
                        panel.open = false
                    } else {
                        if (targetX !== panel.x) {
                            horizontalBehavior.enabled = true
                            panel.x = targetX
                            horizontalBehavior.enabled = false
                        }
                        if (targetY !== panel.y) {
                            verticalBehavior.enabled = true
                            panel.y = targetY
                            verticalBehavior.enabled = false
                        }
                    }
                }
            }
        }

        onPressed: {
            panel._direction = 0
            panel._lastPos = panel._isVertical ? panel.y : panel.x
        }
        onPositionChanged: {
            var pos = panel._isVertical ? panel.y : panel.x
            panel._direction = (_direction + pos - _lastPos) / 2
            panel._lastPos = panel.y
        }
    }
}
