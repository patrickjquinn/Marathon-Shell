/****************************************************************************************
**
** Copyright (C) 2013-2021 Jolla Ltd.
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
import Sailfish.Silica.private 1.0
import "private/Util.js" as Util
import "private/RemorseItem.js" as RemorseItem
import "private"

SilicaMouseArea {
    id: contextMenu

    property bool active
    property bool closeOnActivation: true
    property bool hasContent: contentColumn.children.length > 0
    property Item container
    property alias backgroundColor: background.color
    property alias highlightColor: highlightBar.color

    property int _openAnimationDuration: 200
    property Item _highlightedItem
    property Flickable _flickable
    property bool _flickableMoved
    property Item _parentMouseArea
    property bool _closeOnOutsideClick: true
    property bool _open
    property bool _expanded: height == contentColumn.height && height > 0
    property real _expandedPosition
    property real _targetHeight
    property Item _page
    property bool _activeAllowed: (!_page || _page.status !== PageStatus.Inactive) && Qt.application.active
    readonly property alias _displayHeightAnimating: displayHeightAnimation.running

    property Item _activeMenuItem

    signal activated(int index)
    signal closed

    default property alias children: contentColumn.data
    property alias _contentColumn: contentColumn

    x: {
        if (!parent)
            return 0

        var offset = 0
        var p = parent

        if (_flickable) {
            if (_flickable.width != width) {
                offset = (width - _flickable.width) / 2
            }

            offset -= _flickable.contentX
        }

        do {
            offset += p.x
            p = p.parent
        } while (p != null && _flickable && p !== _flickable.contentItem)

        return -offset
    }
    height: _displayHeight
    width: _flickable !== null ? _flickable.width : (parent ? parent.width : 0)
    parent: null
    clip: true
    enabled: contextMenu._expanded
    anchors.bottom: parent ? parent.bottom : undefined

    onPressed: {
        _flickableMoved = false
        _highlightMenuItem(mouse.y - contentColumn.y)
    }
    onPositionChanged: _updatePosition(mouse.y - contentColumn.y)
    onCanceled: _setHighlightedItem(null)
    onReleased: {
        if (_flickableMoved) {
            // If the flickable has moved during open, the user has made a selection
            // inadvertantly; ignore the activation
            _flickableMoved = false
        } else if (_highlightedItem !== null) {
            _activatedMenuItem(_highlightedItem)
        }
    }
    drag.target: Item {}

    VerticalAutoScroll.modal: _closeOnOutsideClick
    VerticalAutoScroll.keepVisible: _open
    VerticalAutoScroll.animated: false
    VerticalAutoScroll.restorePosition: true

    Component {
        id: removeOpacityEffect
        Item {
            property var source
            ShaderEffect {
                x: Math.min(0, contextMenu.x)
                width: Math.max(parent.width, contextMenu.width)
                // Try to avoid resizing the layer due to expansion animation
                height: Math.max(parent.height, _targetHeight)
                property var source: parent.source
                fragmentShader: "
                    uniform sampler2D source;
                    varying highp vec2 qt_TexCoord0;
                    void main(void)
                    {
                        gl_FragColor = texture2D(source, qt_TexCoord0);
                    }
                    "
            }
        }
    }

    onHeightChanged: {
        if (_highlightedItem) {
            // reposition the highlightBar
            highlightBar.highlight(_highlightedItem, contentColumn)
        }
    }

    onActiveChanged: {
        if (active) {
            contextMenu._open = true
        }

        if (_parentMouseArea) {
            _parentMouseArea.preventStealing = active
        }

        RemorseItem.activeChanged(contextMenu, active)
    }

    on_ActiveAllowedChanged: {
        if (!_activeAllowed && active) {
            close()
        }
    }

    function open(item) {
        if (item) {
            parent = item
            if (hasContent) {
                _parentMouseArea = _closeOnOutsideClick ? _findBackgroundItem(item) : null
                _flickable = Util.findFlickable(item)
                _expandedPosition = -1
                _targetHeight = parent.height + _getDisplayHeight()

                active = true

                _page = Util.findPage(contextMenu)
            } else {
                parent = null
                _page = null
            }
        } else {
            console.log("ContextMenu::open() called with an invalid item")
        }
    }

    function close() {
        active = false
        _parentMouseArea = null
    }

    function show(item) {
        console.warn("ContextMenu::show is deprecated in Sailfish Silica package 0.25.6 (Dec 2017), use ContextMenu::open instead.")
        console.trace()
        open(item)
    }

    function hide() {
        console.warn("ContextMenu::hide is deprecated in Sailfish Silica package 0.25.6 (Dec 2017), use ContextMenu::close instead.")
        console.trace()
        close()
    }

    // Called from number animation of _displayHeight behavior when animation has finished.
    function _reset() {
        // The _contentHeight (and the animated _displayHeight following it) may be reduced to 0 if
        // active is false or all of the items in the menu are hidden which can happen as a
        // side effect of the menu or its window being hidden.
        if (_displayHeight <= 0 && _contentHeight <= 0) {
            close() // If the menu was effectively closed as a result of being hidden, explicitly close it now.
            parent = null
            _page = null
            contextMenu.closed()

            _setHighlightedItem(null)
            contextMenu._open = false

            if (_activeMenuItem) {
                _activeMenuItem.delayedClick()
                _activeMenuItem = null
            }
        }
    }

    function _parentDestroyed() {
        parent = null
        _page = null
    }

    function _findBackgroundItem(item) {
        if (item.hasOwnProperty("preventStealing") && item.pressed) {
            return item
        }

        if (!item.hasOwnProperty("children")) {
            return null
        }

        var parent = item
        for (var i=0; i < parent.children.length; i++) {
            var child = parent.children[i]
            if (child.hasOwnProperty("preventStealing") && child.pressed) {
                return child
            }
            var descendant = _findBackgroundItem(child)
            if (descendant) {
                return descendant
            }
        }

        return null
    }

    function _highlightMenuItem(yPos) {
        var xPos = width/2
        var child = Util.childAt(contentColumn, xPos, yPos)
        if (!child) {
            _setHighlightedItem(null)
            return
        }
        var parentItem
        while (child) {
            if (child && child.hasOwnProperty("__silica_menuitem") && child.enabled) {
                _setHighlightedItem(child)
                break
            }
            parentItem = child
            yPos = parentItem.mapToItem(child, xPos, yPos).y
            child = Util.childAt(parentItem, xPos, yPos)
        }
    }

    function _setHighlightedItem(item) {
        if (item === _highlightedItem) {
            return
        }
        if (_highlightedItem) {
            _highlightedItem.down = false
        }
        _highlightedItem = item
        if (_highlightedItem) {
            highlightBar.highlight(_highlightedItem, contentColumn)
            _highlightedItem.down = true
        } else {
            highlightBar.clearHighlight()
        }
    }

    function _activatedMenuItem(item) {
        _foreachMenuItem(function (menuItem, index) {
            if (menuItem === item && menuItem.enabled) {
                menuItem.clicked()
                _activeMenuItem = menuItem
                contextMenu.activated(index)
                if (contextMenu.closeOnActivation) {
                    delayedHiding.restart()
                }
                return false
            }
            return true
        })
    }

    function _updatePosition(y) {
        if (_flickableMoved && _expanded) {
            if (_expandedPosition < 0.0) {
                _expandedPosition = y
            } else if (Math.abs(y - _expandedPosition) > (Theme.itemSizeSmall / 2)) {
                // The user has moved a reasonable amount since the menu opened; re-enable
                _flickableMoved = false
            }
        }
        if (!_flickableMoved) {
            _highlightMenuItem(y)
        }
    }

    function _getDisplayHeight() {
        var total = 0
        for (var i=0; i<children.length; i++) {
            var childItem = children[i]
            if (childItem.visible && childItem.width > 0 && childItem.height > 0) {
                if (childItem.layer.enabled && childItem.layer.effect) {
                    // This child has a layer with an effect applied.
                    // The ShaderEffect will have been made a sibling, with
                    // setTransparentForPositioner(true). We can't query for
                    // isTransparentForPositioner, so instead we ignore this item
                    // and add the layer's height instead, which will be the same as ours.
                    continue
                }
                total += childItem.height
            }
        }
        return total
    }

    function _foreachMenuItem(func) {
        var menuItemIndex = 0
        for (var i=0; i<children.length; i++) {
            if (children[i].hasOwnProperty("__silica_menuitem")) {
                if (!func(children[i], menuItemIndex)) {
                    return
                }
                menuItemIndex++
            }
        }
    }

    Binding {
        when: active && contextMenu._closeOnOutsideClick
        target: __silica_applicationwindow_instance
        property: "_dimScreen"
        value: true
    }

    states: [
        State {
            when: contextMenu.parent && contextMenu._closeOnOutsideClick && (active || displayHeightAnimation.running)
            PropertyChanges {
                target: contextMenu.parent
                layer.effect: removeOpacityEffect
                layer.enabled: true
                layer.smooth: true
                layer.sourceRect: Qt.rect(Math.min(0, contextMenu.x),
                                          0,
                                          Math.max(contextMenu.parent ? contextMenu.parent.width : 0, contextMenu.width),
                                          Math.max(contextMenu.parent ? contextMenu.parent.height : 0, _targetHeight))
            }
        }
    ]

    Connections {
        target: _flickable && _flickable.flickableDirection != Flickable.HorizontalFlick ? _flickable : null
        onContentYChanged: _flickableMoved = true
    }

    Connections {
        // TODO: replace with Connections.enabled binding (pending Qt 5.7+)
        ignoreUnknownSignals: true
        target: _expanded ? _parentMouseArea : null
        onPositionChanged: _updatePosition(contentColumn.mapFromItem(_parentMouseArea, mouse.x, mouse.y).y)
        onReleased: contextMenu.released(mouse)
    }

    Rectangle {
        id: background

        anchors.fill: parent
        color: contextMenu.palette.highlightBackgroundColor
        opacity: Theme.highlightBackgroundOpacity
        InverseMouseArea {
            anchors.fill: parent
            enabled: active && _closeOnOutsideClick
            stealPress: true
            onPressedOutside: close()
        }

        states: State {
            when: contextMenu._open
                  && contextMenu.parent !== null
                  && contextMenu._flickable !== null
                  && _flickable.flickableDirection === Flickable.HorizontalFlick
            PropertyChanges {
                target: contextMenu._flickable
                interactive: contextMenu._closeOnOutsideClick

                height: contextMenu.parent.height
            }
        }
    }

    HighlightBar {
        id: highlightBar
        height: _highlightedItem ? _highlightedItem.height : Theme.itemSizeSmall
    }

    Column {
        id: contentColumn

        width: parent.width
        anchors.bottom: parent.bottom
    }

    Timer {
        id: delayedHiding

        interval: 10
        onTriggered: contextMenu.close()
    }

    readonly property real _contentHeight: contentColumn.children.length, active && contentColumn.height > 0
                                           ? _getDisplayHeight() : 0
    property real _displayHeight: _contentHeight
    Behavior on _displayHeight {
        NumberAnimation {
            id: displayHeightAnimation
            duration: contextMenu._openAnimationDuration
            easing.type: Easing.InOutQuad

            onRunningChanged: {
                if (!running) {
                    delayedReset.restart()
                }
            }
        }
    }

    Timer {
        id: delayedReset

        interval: 10
        onTriggered: contextMenu._reset()
    }

    Component.onDestruction: {
        if (active) {
            RemorseItem.activeChanged(contextMenu, false)
        }
        // This guarantees that the interactive property of the flickable
        // is restored back to its original state.
        _open = false
        active = false
    }
}
