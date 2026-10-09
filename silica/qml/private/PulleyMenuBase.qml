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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/PulleyMenuBase.qml
// Modified by Shipwright for Qt 6: geometry bindings guarded while `flickable` is still null (set in Component.onCompleted), which warned at creation.
// Modified by Shipwright for Qt 6: optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are.
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (11 places).
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (9 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: the inline GLSL is a compiled Qt 6 shader (qml/shaders/pulley.frag); no layer on the software scene graph.
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.0
import QtQuick as KeelQuick // Modified by Shipwright for Qt 6: GraphicsInfo (newer than this file's QtQuick import)
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "Util.js" as Util
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below
import Sailfish.Silica.private 1.0 as KeelPrivate // Modified by Shipwright for Qt 6: Util._keelOptionalObject

SilicaMouseArea {
    id: pulleyBase

    /*
    The layout model for PullDownMenu/PushUpMenu is as follows:

         ---                        +--------------
          |                         |
          | Flickable.topMargin     | PullDownMenu
          |                         |                 ---
    ---  ---      Flickable.originY +--------------    |
     |                              |                  |
     | Flickable.contentHeight      | Content area     | flickable space
     |                              |                  |
    ---  ---                        +--------------    |
          |                         |                 ---
          | Flickable.bottomMargin  | PushUpMenu
          |                         |
         ---                        +--------------

    Within the PullDownMenu, space is allocated as follows:

    +--------------  ---                             ---
    | topMargin       |                               |
    +--------------   |                               |
    |                 |                               |
    | contentColumn   | PullDownMenu._activeHeight    |
    |                 |                               |
    +--------------   |           PullDownMenu.height |
    | bottomMargin    |                               |
    +--------------  ---                              |
    | spacing                                         |
    +--------------                                  ---

    When PullDownMenu.active is false, PullDownMenu.height is equal to
    PullDownMenu.spacing + PullDownMenu._inactiveHeight.  Some element of
    the menu may be displayed inside the flickable space by placing it
    within the _inactiveHeight.

    The spacing allocation is left empty between the bottom of the menu
    and the position of the Flickable's content.  This empty space is
    visible even if the menu is inactive.

    PushUpMenu is allocated as follows:

    +--------------                                  ---
    | spacing                                         |
    +--------------  ---                              |
    | topMargin       |                               |
    +--------------   |                               |
    |                 |                               |
    | contentColumn   | PushUpMenu._activeHeight      |
    |                 |                               |
    +--------------   |             PushUpMenu.height |
    | bottomMargin    |                               |
    +--------------  ---                             ---
    */

    property bool active                // True if the menu is active
    property real spacing               // Space allocated between the menu border and the flickable content
    property Flickable flickable
    property Item menuItem
    property bool busy
    property bool quickSelect

    property real _inactiveHeight       // Height to show when the menu is inactive
    property real _activeHeight         // Height to show when the menu is active
    property real _inactivePosition     // The position to return to when becoming inactive
    property real _finalPosition        // The position where the menu is at the limit of its extent
    property bool _atInitialPosition: Math.abs(flickable.contentY - _inactivePosition) < 1.0 && !active
    property bool _atFinalPosition: Math.abs(flickable.contentY - _finalPosition) < 1.0 && active
    property real _contentEnd
    property real _menuIndicatorPosition // The position of the highlight when the menu is closed
    property real _menuItemHeight: screen.sizeCategory <= KeelSilica.Screen.Medium ? Theme.itemSizeExtraSmall : Theme.itemSizeSmall
    property real _menuItemActivationThreshold: _menuItemHeight
                                                + ((_isPullDownMenu && KeelSilica.Screen.hasCutouts && _page && _page.isPortrait)
                                                   ? KeelSilica.Screen.topCutout.height : 0)

    property bool _activationInhibited
    property bool _activationPermitted: visible && enabled && _atInitialPosition && !_activationInhibited

    property color highlightColor: palette.highlightBackgroundColor
    property color backgroundColor: palette.highlightBackgroundColor
    property int colorScheme: palette.colorScheme

    property bool _bounceBackEnabled: false
    property bool _bounceBackRunning: bounceBackAnimation.running

    property real _snapThreshold: Theme.itemSizeSmall
    property real _snapCalculationThreshold: Theme.itemSizeSmall * 3
    property real _snapCalculationVelocity: flickable
                                            ? Math.pow(2 * flickable.flickDeceleration * _snapCalculationThreshold, 0.5)
                                            : 0

    property bool _inListView: flickable !== null && flickable.hasOwnProperty('highlightRangeMode')
    property bool _changingListView: false
    property real _shadowHeight: Theme.itemSizeExtraLarge
    property Item _page
    property bool _activeAllowed: (!_page || _page.status != PageStatus.Inactive) && Qt.application.active
    property bool _activeDimmer
    property bool _hinting
    property real _highlightIndicatorPosition
    property bool _doClick
    property bool _quickSelected
    property bool _pageActive: _page && _page.status === PageStatus.Active

    property QtObject _ngfEffect

    // Provides content column handle for PulleyMenuLogic -- fetched from c++
    property Item _contentColumn
    // "Type" of PulleyMenu, for PulleyMenuLogic
    property alias _isPullDownMenu: logic.pullDownType
    property alias _dragDistance: logic.dragDistance

    z: 10000 // we want the menu indicator and its dimmer to appear above content
    // Modified by Shipwright for Qt 6: no flickable until Component.onCompleted (avoids TypeErrors)
    x: flickable ? flickable.contentX + (flickable.width - width)/2 : 0
    width: flickable && flickable.width ? Math.min(flickable.width,
                                      screen.sizeCategory > KeelSilica.Screen.Medium ? KeelSilica.Screen.width*0.7 : KeelSilica.Screen.width)
                           : KeelSilica.Screen.width
    height: _activeHeight + spacing

    // Modified by Shipwright for Qt 6: no layer on the software scene graph, which runs no shaders
    layer.enabled: KeelQuick.GraphicsInfo.api !== KeelQuick.GraphicsInfo.Software
                   && (active || (flickable.dragging && __silica_applicationwindow_instance._dimmingActive))
    layer.smooth: true
    layer.sourceRect: Qt.rect(0,
                              _isPullDownMenu ? 0 : -_shadowHeight,
                              pulleyBase.width,
                              pulleyBase.height + _shadowHeight)
    layer.effect: Item {
        property var source

        ShaderEffect {
            property var source: parent.source
            property real flickOpacity: pulleyBase.flickable ? pulleyBase.flickable.contentItem.opacity : 1.0 // Modified by Shipwright for Qt 6: qualified

            y: pulleyBase._isPullDownMenu ? 0 : -pulleyBase._shadowHeight // Modified by Shipwright for Qt 6: qualified
            width: pulleyBase.width
            height: pulleyBase.height + pulleyBase._shadowHeight // Modified by Shipwright for Qt 6: qualified
            // Modified by Shipwright for Qt 6: Qt 6 takes a compiled shader (qml/shaders/pulley.frag)
            fragmentShader: "qrc:/qt/qml/Sailfish/Silica/shaders/pulley.frag.qsb"
        }
    }

    states: [
        State {
            name: "expanded"
            PropertyChanges {
                target: flickable
                highlightRangeMode: ListView.NoHighlightRange
                snapMode: ListView.NoSnap
            }
        }
    ]

    Timer {
        // Update state in timer as changing highlightRangeMode or snapMode
        // can cause view position change, which could affect active, resulting
        // in a binding loop.
        id: expandedStateTimer

        interval: 1
        onTriggered: {
            // highlightRangeMode and snapMode are changed sequentially, rather than
            // atomically -- this causes the ListView to 'fixup' while in an
            // intermediate state, snapping us back to 0,0
            pulleyBase._changingListView = true // Modified by Shipwright for Qt 6: qualified
            var oldContentY = pulleyBase.flickable.contentY // Modified by Shipwright for Qt 6: qualified
            pulleyBase.state = pulleyBase.active ? "expanded" : "" // Modified by Shipwright for Qt 6: qualified
            pulleyBase.flickable.contentY = oldContentY // Modified by Shipwright for Qt 6: qualified
            pulleyBase._changingListView = false // Modified by Shipwright for Qt 6: qualified
        }
    }

    drag.target: Item {}

    onVisibleChanged: {
        if (visible) {
            _reposition()
        } else if (pulleyBase) {
            // sometimes visible goes to false during destruction
            // make sure pulley exists in the conditional above so
            // hide() call is not propagated through parent QML contexts
            // to the parent page container's hide() in PageStack
            hide()
            close(true)
        }
    }
    onEnabledChanged: {
        if (!enabled) {
            hide()
            close()
        }
    }

    onFlickableChanged: {
        if (flickable) {
            parent = flickable.contentItem
            _addToFlickable(flickable)
            _page = Util.findPage(flickable)
            _reposition()
        }
    }

    // Modified by Shipwright for Qt 6: signal parameter declared
    onPressed: function(mouse) {
        _highlightMenuItem(contentColumn, mouse.y - contentColumn.y)
    }
    // Modified by Shipwright for Qt 6: signal parameter declared
    onPositionChanged: function(mouse) { _highlightMenuItem(contentColumn, mouse.y - contentColumn.y) }
    onReleased: {
        if (menuItem) {
            menuItem.clicked()
        }
        hide()
    }
    onActiveChanged: {
        if (!active) {
            if (menuItem) {
                menuItem.delayedClick()
            }

            menuItem = null
        }

        _bounceBackEnabled = active
        if (_inListView) {
            expandedStateTimer.restart()
        }
        highlightItem._highlightedItemPosition = _isPullDownMenu ? -KeelSilica.Screen.height : KeelSilica.Screen.height
        if (!active) {
            highlightItem.clearHighlight()
        }
        _setMenuItemsInverted(active)
    }

    on_ActiveAllowedChanged: {
        if (!_activeAllowed && active) {
            close(true)
        }
    }

    on_AtFinalPositionChanged: _setMenuItemsInverted(!_atFinalPosition)

    on_PageActiveChanged: if (_pageActive) highlightItem.state = "enterView"

    Binding {
        when: pulleyBase.active && pulleyBase._atFinalPosition && !pulleyBase.flickable.dragging && !pulleyBase._quickSelected // Modified by Shipwright for Qt 6: qualified
        target: __silica_applicationwindow_instance
        property: "_dimScreen"
        value: pulleyBase.active && !pulleyBase._bounceBackRunning // Modified by Shipwright for Qt 6: qualified
    }

    function _findMenuItem(item: var, allItems: var): var { // Modified by Shipwright for Qt 6: typed
        if (!allItems && (!item.visible || !item.enabled)) {
            return null
        }
        if (item.hasOwnProperty("__silica_menuitem")) {
            return item
        }
        for (var i = 0; i < item.children.length; ++i) {
            var mi = _findMenuItem(item.children[i])
            if (mi) {
                return mi
            }
        }
        return null
    }

    function _quickSelectItem(parentItem: var): var { // Modified by Shipwright for Qt 6: typed
        if (quickSelect) {
            var child = null
            var count = 0
            for (var i = 0; i < parentItem.children.length && count < 2; i++) {
                var item = _findMenuItem(parentItem.children[i])
                if (item) {
                    child = item
                    count++
                }
            }
            if (count == 1) {
                return child
            }
        }

        return null
    }

    function _quickSelectMenuItem(parentItem: var, yPos: var): var { // Modified by Shipwright for Qt 6: typed
        if (quickSelect) {
            var child = _quickSelectItem(parentItem)
            if (child) {
                _quickSelected = true
                var xPos = width/2
                if ((_isPullDownMenu && parentItem.mapToItem(child, xPos, yPos).y <= _menuItemHeight)
                        || (!_isPullDownMenu && parentItem.mapToItem(child, xPos, yPos).y >= 0)) {
                    if (flickable.dragging) {
                        menuItem = child
                    }
                    highlightItem.highlight(child, pulleyBase)
                    return child
                }
            } else {
                _quickSelected = false
            }
        } else {
            _quickSelected = false
        }

        return null
    }

    function _highlightMenuItem(parentItem: var, yPos: var): void { // Modified by Shipwright for Qt 6: typed
        var child = _quickSelectMenuItem(parentItem, yPos)
        if (child) {
            return
        }

        var xPos = width / 2

        // Only try to highlight if we haven't dragged to the final position
        if (!flickable.dragging || !_atFinalPosition) {
            child = Util.childAt(parentItem, xPos, yPos)
        }
        while (child) {
            if (child && child.hasOwnProperty("__silica_menuitem") && child.enabled && child.visible) {
                menuItem = child
                yPos = parentItem.mapToItem(child, xPos, yPos).y
                highlightItem.highlight(menuItem, pulleyBase, logic.dragDistance <= _contentEnd && !_atFinalPosition)
                break
            }
            parentItem = child
            yPos = parentItem.mapToItem(child, xPos, yPos).y
            child = Util.childAt(parentItem, xPos, yPos)
        }
        if (!child) {
            menuItem = null
            highlightItem.clearHighlight()
        }
    }

    function _hasMenuItems(): var { // Modified by Shipwright for Qt 6: typed
        for (var i = 0; i < _contentColumn.children.length; ++i) {
            if (_findMenuItem(_contentColumn.children[i])) {
                return true
            }
        }

        return false
    }

    function _forEachItem(func: var): void { // Modified by Shipwright for Qt 6: typed
        for (var i = 0; i < _contentColumn.children.length; ++i) {
            var item = _findMenuItem(_contentColumn.children[i], true)
            if (item) {
                func(item)
            }
        }
    }

    function _setMenuItemsInverted(inverted: var): void { // Modified by Shipwright for Qt 6: typed
        _forEachItem(function (item) { item._invertColors = inverted })
    }

    function _handleClicked(): void { // Modified by Shipwright for Qt 6: typed
        if (active && menuItem) {
            menuItem.clicked()
        }
        hide()
        _doClick = false
    }

    function hide(): void { // Modified by Shipwright for Qt 6: typed
        if (active && _bounceBackEnabled) {
            delayedBounceTimer.restart()
        }
    }

    function cancelBounceBack(): void { // Modified by Shipwright for Qt 6: typed
        _bounceBackEnabled = false
        delayedBounceTimer.stop()
        bounceBackAnimation.stop()
    }

    function close(immediate: var): void { // Modified by Shipwright for Qt 6: typed
        if (!active) {
            // can't close what isn't open, and we
            // don't want to reposition unnecessarily
            return
        }

        if (immediate === true) {
            _forceReposition()
        } else {
            flickAnimation.stop()
            if (!flickable.dragging && !bounceBackAnimation.running) {
                _reposition()
            }
        }
    }

    HighlightBar {
        id: highlightItem

        y: {
            if (!pulleyBase.active) { // Modified by Shipwright for Qt 6: qualified
                return pulleyBase._menuIndicatorPosition // Modified by Shipwright for Qt 6: qualified
            }

            if (highlightedItem
                    || (!pulleyBase.flickable.dragging && pulleyBase._atFinalPosition)) { // Modified by Shipwright for Qt 6: qualified
                return _highlightedItemPosition
            }
            return pulleyBase._highlightIndicatorPosition // Modified by Shipwright for Qt 6: qualified
        }

        height: highlightedItem ? highlightedItem.height : pulleyBase._menuItemHeight // Modified by Shipwright for Qt 6: qualified

        yAnimationDuration: 120
        color: pulleyBase.highlightColor
        audioEnabled: pulleyBase.flickable.dragging || pulleyBase.quickSelect // Modified by Shipwright for Qt 6: qualified
        opacityAnimationDuration: pulleyBase._atInitialPosition || pulleyBase._bounceBackRunning ? 400 : Theme.minimumPressHighlightTime // Modified by Shipwright for Qt 6: qualified
        opacity: {
            if (highlightedItem) {
                return Theme.highlightBackgroundOpacity
            } else if ((!pulleyBase.active && !pulleyBase._hinting) || pulleyBase._bounceBackRunning) { // Modified by Shipwright for Qt 6: qualified
                return _inactiveOpacity
            } else if (!_hasMenuItems(pulleyBase._contentColumn)) { // Modified by Shipwright for Qt 6: qualified
                return Theme.highlightBackgroundOpacity * (1.0 - logic.dragDistance / Theme.paddingMedium)
            } else {
                // opacity on starts with 1.5 multiplier (could use something cleaner?),
                // goes downwards with drag until lower part takes over,
                // finally ensuring item hidden when dragged beyond the menu items
                return Theme.highlightBackgroundOpacity
                        * Math.max(1.5 - logic.dragDistance / pulleyBase._menuItemHeight, // Modified by Shipwright for Qt 6: qualified
                                   (logic.dragDistance <= (pulleyBase._contentEnd + pulleyBase._menuItemActivationThreshold) // Modified by Shipwright for Qt 6: qualified
                                    && !flickAnimation.running)
                                   ? 0.5 : 0.0)
            }
        }

        property real _inactiveOpacity: 1.0

        Timer {
            id: busyTimer

            running: pulleyBase.busy && !pulleyBase.active && Qt.application.active // Modified by Shipwright for Qt 6: qualified
            interval: 500
            repeat: true
            onRunningChanged: highlightItem._inactiveOpacity = 1.0
            onTriggered: highlightItem._inactiveOpacity = highlightItem._inactiveOpacity >= 0.99
                         ? Theme.highlightBackgroundOpacity : 1.0
        }

        states: [
            State {
                name: "click"
                when: pulleyBase._doClick && !pulleyBase._quickSelected // Modified by Shipwright for Qt 6: qualified
            },
            State {
                name: "quickselectclick"
                when: pulleyBase._doClick && pulleyBase._quickSelected // Modified by Shipwright for Qt 6: qualified
            },
            State {
                name: "enterView"
            },
            State {
                name: "bounceBack"
                when: pulleyBase._bounceBackRunning && pulleyBase.active // Modified by Shipwright for Qt 6: qualified
                PropertyChanges {
                    target: highlightItem
                    y: _menuIndicatorPosition
                }
            }
        ]

        Timer {
            id: earlyClickTimer

            interval: 1
            onTriggered: pulleyBase.menuItem.earlyClick() // Modified by Shipwright for Qt 6: qualified
        }

        Rectangle {
            readonly property bool active: palette.colorScheme === Theme.DarkOnLight
                                           && !(pulleyBase.flickable.dragging && pulleyBase.active) // Modified by Shipwright for Qt 6: qualified

            width: parent.width
            height: active ? 2* Math.round(Theme.pixelRatio) : 0
            y: pulleyBase._isPullDownMenu ? parent.height : -height // Modified by Shipwright for Qt 6: qualified
            opacity: active ? 1.0 : 0.0
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }}
            Behavior on opacity { FadeAnimator {}}
            color: Qt.tint(pulleyBase.backgroundColor, Qt.rgba(0, 0, 0, 0.15))
        }

        transitions: [
            Transition {
                onRunningChanged: {
                    if (running) {
                        earlyClickTimer.restart()
                    } else {
                        _handleClicked()
                    }
                }

                to: "click"
                SequentialAnimation {
                    FadeAnimator {
                        target: highlightItem
                        duration: 110
                        from: Theme.highlightBackgroundOpacity // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity/2
                    }
                    FadeAnimator {
                        target: highlightItem
                        duration: 55
                        from: Theme.highlightBackgroundOpacity/2 // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity
                    }
                    FadeAnimator {
                        target: highlightItem
                        duration: 110
                        from: Theme.highlightBackgroundOpacity // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity/2
                    }
                    FadeAnimator {
                        target: highlightItem
                        duration: 55
                        from: Theme.highlightBackgroundOpacity/2 // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity
                    }
                    // QTBUG-70365: No PauseAnimator animation element available
                    // Mimick PauseAnimation. SequentialAnimation is only
                    // non-blocking if all sub-animations are animators.
                    FadeAnimator {
                        target: highlightItem
                        duration: 45
                        from: Theme.highlightBackgroundOpacity // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity
                    }
                }
            },
            Transition {
                onRunningChanged: running ? earlyClickTimer.restart() : _handleClicked()

                to: "quickselectclick"
                SequentialAnimation {
                    FadeAnimator {
                        target: highlightItem
                        duration: 120
                        from: Theme.highlightBackgroundOpacity // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity/2
                    }
                    FadeAnimator {
                        target: highlightItem
                        duration: 60
                        from: Theme.highlightBackgroundOpacity/2 // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity
                    }
                    FadeAnimator {
                        target: highlightItem
                        duration: 50
                        from: Theme.highlightBackgroundOpacity // QTBUG-70366
                        to: Theme.highlightBackgroundOpacity
                    }
                }
            },
            Transition {
                to: "enterView"
                SequentialAnimation {
                    FadeAnimation {
                        target: highlightItem
                        duration: 300
                        to: Theme.highlightBackgroundOpacity
                    }
                    FadeAnimation {
                        target: highlightItem
                        duration: 600
                        to: highlightItem._inactiveOpacity
                    }
                    ScriptAction {
                        script: highlightItem.state = ""
                    }
                }
            },
            Transition {
                to: "bounceBack"
                ScriptAction {
                    script: highlightItem._transientAnimateY = false
                }
                SmoothedAnimation {
                    target: highlightItem
                    property: "y"
                    to: pulleyBase._menuIndicatorPosition // Modified by Shipwright for Qt 6: qualified
                    duration: 400
                    velocity: -1
                }
            }
        ]
    }

    function _interceptFlick(): void { // Modified by Shipwright for Qt 6: typed
        // Do not permit flicking inside the menu (unless it is a small flick that does not present
        // a danger of accidentally selecting the wrong item)
        if (active && !_quickSelected && (Math.abs(flickable.verticalVelocity) > Theme.dp(500))) {
            var opening = _isPullDownMenu ? flickable.verticalVelocity < 0
                                          : flickable.verticalVelocity > 0
            flickAnimation.to = opening ? _finalPosition : _inactivePosition
            flickAnimation.duration = 300
            flickAnimation.restart()
            menuItem = null
            highlightItem.clearHighlight()
        } else if (!active) {
            logic.monitorFlick()
        }
    }
    function _bounceBack(): void { // Modified by Shipwright for Qt 6: typed
        if (!flickAnimation.running) {
            if (menuItem) {
                _doClick = true
            } else if (_atFinalPosition) {
                var quickSelectItem = _quickSelectItem(_contentColumn)
                if (quickSelectItem) {
                    menuItem = quickSelectItem
                    _doClick = true
                }
            } else {
                hide()
            }
        }
    }
    function _reposition(): void { // Modified by Shipwright for Qt 6: typed
        if (active) {
            _forceReposition()
        }
    }
    function _forceReposition(): void { // Modified by Shipwright for Qt 6: typed
        if (flickable) {
            _stopAnimations()
            flickable.contentY = _inactivePosition
        }
    }
    function _stopAnimations(): void { // Modified by Shipwright for Qt 6: typed
        if (active) {
            flickAnimation.stop()
            bounceBackAnimation.stop()
        } else {
            highlightItem.state = ""
            snapAnimation.stop()
        }
    }

    function _updateFlickable(): void { // Modified by Shipwright for Qt 6: typed
        var item = Util.findFlickable(pulleyBase)
        if (item) {
            flickable = item
            parent = item.contentItem
            _addToFlickable(item)
        }
    }

    PulleyMenuLogic {
        id: logic

        flickable: pulleyBase.flickable
        onFinalPositionReached: {
            if (pulleyBase.active && pulleyBase._ngfEffect && !pulleyBase.menuItem && !pulleyBase.quickSelect // Modified by Shipwright for Qt 6: qualified
                    && !delayedBounceTimer.running && !bounceBackAnimation.running) {
                pulleyBase._ngfEffect.play() // Modified by Shipwright for Qt 6: qualified
            }
        }

        // void animateFlick(qreal duration, qreal position)
        // Modified by Shipwright for Qt 6: signal parameter declared
        onAnimateFlick: function(duration, position) {
            flickAnimation.duration = duration * 1000
            flickAnimation.to = position
            flickAnimation.restart()
        }
    }

    Connections {
        target: pulleyBase.flickable // Modified by Shipwright for Qt 6: qualified
        ignoreUnknownSignals: true
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onMovementEnded(): void { // Modified by Shipwright for Qt 6: typed
            if (pulleyBase.active) { // Modified by Shipwright for Qt 6: qualified
                if (logic.outOfBounds()) {
                    flickAnimation.to = pulleyBase._finalPosition // Modified by Shipwright for Qt 6: qualified
                    flickAnimation.duration = Math.min(Math.abs(pulleyBase.flickable.contentY - pulleyBase._finalPosition) * 2, 400) // Modified by Shipwright for Qt 6: qualified
                    flickAnimation.restart()
                    pulleyBase.menuItem = null // Modified by Shipwright for Qt 6: qualified
                    highlightItem.clearHighlight()
                } else {
                    _bounceBack()
                }
            } else if (pulleyBase.flickable.height < pulleyBase.flickable.contentHeight - pulleyBase._snapThreshold) { // Modified by Shipwright for Qt 6: qualified
                // If we are close to the menu location, snap to the end
                var dist = pulleyBase.flickable.contentY - pulleyBase._inactivePosition // Modified by Shipwright for Qt 6: qualified
                if (pulleyBase._isPullDownMenu && dist > 0 && dist < pulleyBase._snapThreshold // Modified by Shipwright for Qt 6: qualified
                        || !pulleyBase._isPullDownMenu && dist < 0 && dist > -pulleyBase._snapThreshold) { // Modified by Shipwright for Qt 6: qualified
                    snapAnimation.restart()
                }
            }
        }
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onMovementStarted(): void { _stopAnimations() } // Modified by Shipwright for Qt 6: typed
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onFlickStarted(): void { _interceptFlick() } // Modified by Shipwright for Qt 6: typed
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onContentHeightChanged(): void { if (!pulleyBase.active) close() } // Modified by Shipwright for Qt 6: qualified
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onModelChanged(): void { _forceReposition() } // Modified by Shipwright for Qt 6: typed
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onHeaderChanged(): void { _reposition() } // Modified by Shipwright for Qt 6: typed
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onOriginYChanged(): void { // Modified by Shipwright for Qt 6: typed
            if (bounceBackAnimation.running) {
                bounceBackAnimation.restart()
            }
        }
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onDraggingChanged(): void { // Modified by Shipwright for Qt 6: typed
            if (!pulleyBase.flickable.dragging) { // Modified by Shipwright for Qt 6: qualified
                pulleyBase._activationInhibited = false // Modified by Shipwright for Qt 6: qualified
            }
        }
    }
    Timer {
        id: delayedBounceTimer

        interval: 10
        onTriggered: bounceBackAnimation.restart()
    }
    NumberAnimation {
        id: flickAnimation

        target: pulleyBase.flickable // Modified by Shipwright for Qt 6: qualified
        property: "contentY"
        easing.type: Easing.OutQuad
        onStopped: {
            if (pulleyBase.quickSelect && pulleyBase._quickSelected && pulleyBase._atFinalPosition) { // Modified by Shipwright for Qt 6: qualified
                _bounceBack()
            }
        }
    }
    SmoothedAnimation {
        id: bounceBackAnimation

        duration: 400
        velocity: -1
        target: pulleyBase.flickable // Modified by Shipwright for Qt 6: qualified
        property: "contentY"
        to: pulleyBase._inactivePosition // Modified by Shipwright for Qt 6: qualified
    }
    SmoothedAnimation {
        id: snapAnimation

        duration: 200
        target: pulleyBase.flickable // Modified by Shipwright for Qt 6: qualified
        property: "contentY"
        to: pulleyBase._inactivePosition // Modified by Shipwright for Qt 6: qualified
    }
    InverseMouseArea {
        anchors.fill: parent
        enabled: pulleyBase.active && !pulleyBase._hinting // Modified by Shipwright for Qt 6: qualified
        stealPress: !pulleyBase.flickable.dragging // Modified by Shipwright for Qt 6: qualified
        onPressedOutside: {
            if (!flickAnimation.running && !pulleyBase.flickable.moving) { // Modified by Shipwright for Qt 6: qualified
                if (highlightItem.state !== "click") {
                    pulleyBase.menuItem = null // Modified by Shipwright for Qt 6: qualified
                    hide()
                }
                cancelTouch()
            }
        }
    }

    Component.onCompleted: {
        // avoid hard dependency to ngf module
        // Modified by Shipwright for Qt 6: the optional module may be missing; fail quietly
        try {
            // Modified by Shipwright for Qt 6: made by Util._keelOptionalObject (C++), which compiles it once per engine
            _ngfEffect = KeelPrivate.Util._keelOptionalObject("ngf-pulldown_lock", "import Nemo.Ngf 1.0",
                                              "NonGraphicalFeedback { event: 'pulldown_lock' }", highlightItem)
        } catch (e) {
            _ngfEffect = null
        }
    }

    Component.onDestruction: {
        active = false
    }
}
