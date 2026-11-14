/****************************************************************************************
**
** Copyright (c) 2013-2020 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
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

/****************************************************************************
**
** Copyright (C) 2011 Nokia Corporation and/or its subsidiary(-ies).
** All rights reserved.
** Contact: Nokia Corporation (qt-info@nokia.com)
**
** This file is part of the Qt Components project.
**
** $QT_BEGIN_LICENSE:BSD$
** You may use this file under the terms of the BSD license as follows:
**
** "Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are
** met:
**   * Redistributions of source code must retain the above copyright
**     notice, this list of conditions and the following disclaimer.
**   * Redistributions in binary form must reproduce the above copyright
**     notice, this list of conditions and the following disclaimer in
**     the documentation and/or other materials provided with the
**     distribution.
**   * Neither the name of Nokia Corporation and its Subsidiary(-ies) nor
**     the names of its contributors may be used to endorse or promote
**     products derived from this software without specific prior written
**     permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
** "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
** LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
** A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
** OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
** SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
** LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
** DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
** THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
** OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
** $QT_END_LICENSE$
**
****************************************************************************/

// The PageStack item defines a container for pages and a stack-based
// navigation model. Pages can be defined as QML items or components.

import QtQuick 2.2
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private
import "PageStack.js" as PageStack
import "private"

PageStackBase {
    id: root

    width: parent.width
    height: parent.height

    currentPage: _currentContainer ? _currentContainer.page : null
    backNavigation: currentPage !== null && currentPage.backNavigation && depth > 1
    forwardNavigation: currentPage !== null && currentPage.forwardNavigation
                       && (depth > 1
                           || _currentContainer.attachedContainer !== null
                           || (_pendingContainer !== null
                               && currentPage._forwardDestinationAction !== PageStackAction.Pop))
    navigationStyle: currentPage !== null ? currentPage.navigationStyle : PageNavigation.Horizontal

    readonly property bool acceptAnimationRunning: _pageStackIndicator == null
                                                   ? false : _pageStackIndicator.animatingPosition

    readonly property int _currentOrientation: currentPage ? currentPage.orientation : Orientation.Portrait

    readonly property real _currentWidth: currentPage
                                          ? (currentPage.isLandscape ? _currentContainer.height
                                                                     : _currentContainer.width)
                                          : 0
    readonly property real _currentHeight: currentPage
                                          ? (currentPage.isLandscape ? _currentContainer.width
                                                                     : _currentContainer.height)
                                          : 0

    property real _pageOpacity: 1

    property Component pageBackground

    // Duration of transition animations (in ms)
    property int _transitionDuration: 400

    property Item _pageStackIndicator
    property Item _pendingContainer
    property Item _previousContainer
    property real _flickThreshold: Theme.itemSizeMedium

    // Any currently active PullDownMenu in the page stack
    property Item _activePullDownMenu

    // Inclusive of the input method panel, if open:
    property real _effectiveWidth: parent.width
    property real _effectiveHeight: parent.height

    property bool _dialogAtTop: _currentContainer !== null && _currentContainer.containsDialog

    property bool _preventForwardNavigation: currentPage !== null
                                             && currentPage.forwardNavigation
                                             && (currentPage.canNavigateForward === false)

    // Temporary provision for backward compatibility:
    function pushExtra(page, properties) { return pushAttached(page, properties) }
    function _navigateBack(operationType) { return navigateBack(operationType) }
    function _navigateForward(operationType) { return navigateForward(operationType) }

    // Clears the page stack.
    function clear() {
        return PageStack.clear()
    }

    // Pop an attached page from the top of the stack
    function popAttached(page, operationType) {
        return PageStack.popAttached(page, _normalizeOperationType(operationType))
    }

    // Returns the previous page or a null if the supplied page is the first one.
    function previousPage(fromPage) {
        var fromContainer
        if (fromPage) {
            fromContainer = _findContainer(function (page) { return (page === fromPage) })
            if (!fromContainer) {
                throw new Error("Cannot find previousPage for argument not present in stack: " + fromPage)
            }
        } else {
            fromContainer = _currentContainer
        }

        var container = PageStack.containerBelow(fromContainer)
        return container ? container.page : null
    }

    // Returns the next page or null if the supplied page is the stack top
    function nextPage(fromPage) {
        var fromContainer
        if (fromPage) {
            fromContainer = _findContainer(function (page) { return (page === fromPage) })
            if (!fromContainer) {
                throw new Error("Cannot find nextPage for argument not present in stack: " + fromPage)
            }
        } else {
            fromContainer = _currentContainer
        }

        var container = PageStack.containerAbove(fromContainer)
        if (container) {
            return container.page
        } else if (fromContainer.attachedContainer) {
            return fromContainer.attachedContainer.page
        } else {
            return null
        }
    }

    // Iterates through all pages (top to bottom) and invokes the specified function.
    // If the specified function returns true the search stops and the find function
    // returns the page that the iteration stopped at. If the search doesn't result
    // in any page being found then null is returned.
    function find(func) {
        var container = PageStack.find(func)
        return container ? container.page : null
    }

    function _findContainer(func) {
        return PageStack.find(func)
    }

    function _containerBelow(container) {
        return PageStack.containerBelow(container)
    }

    // TODO: navigate back/forward fail when operationType is PageStackAction.Immediate

    // Navigate back one page by popping the page stack.
    function navigateBack(operationType, direction) {
        if (!backNavigation) {
            return null
        }
        if (direction === undefined) {
            if (horizontalNavigationStyle) {
                direction = PageNavigation.Left
            } else {
                direction = PageNavigation.Down
            }
        }

        snapBackAnimation.clearTarget(false)

        operationType = _normalizeOperationType(operationType)

        if (_currentContainer !== null) {
            if (_currentContainer.attached) {
                return PageStack.exitAttached(operationType)
            }

            _currentContainer.navigation = PageNavigation.Back
            _currentContainer.direction = direction
        }
        return pop(undefined, operationType)
    }

    // Navigate forward one page by popping the page stack.
    function navigateForward(operationType) {
        if (!forwardNavigation) {
            return null
        }

        if (_preventForwardNavigation) {
            if (currentPage && currentPage.hasOwnProperty('__silica_dialog')) {
                currentPage.acceptBlocked()
            }

            // Flash briefly to indicate that forward navigation is not possible
            flash.flashPage()

            // Return the page to correct position, if it has been dragged out of position
            snapBackAnimation.duration = _calculateDuration(0, _currentContainer.dragOffset,
                                                            _currentContainer.transitionLength)
            snapBackAnimation.restart()
            return null
        }

        snapBackAnimation.clearTarget(false)

        operationType = _normalizeOperationType(operationType)

        if (_currentContainer !== null) {
            if (_currentContainer.attachedContainer) {
                return PageStack.enterAttached(_currentContainer.attachedContainer, operationType)
            }

            _currentContainer.navigationPending = PageNavigation.Forward
            _currentContainer.navigation = PageNavigation.Forward
            _currentContainer.direction = PageNavigation.Right
        }
        if (_pendingContainer !== null) {
            return PageStack.pushPending(operationType)
        }
        return pop(undefined, operationType)
    }

    function openDialog(dialog, properties, operationType) {
        console.log('Warning: openDialog is deprecated - please use pageStack.push() instead.')
        return push(dialog, properties, operationType)
    }

    function replaceWithDialog(dialog, properties, operationType) {
        console.log('Warning: replaceWithDialog is deprecated - please use pageStack.replace() instead.')
        return replace(dialog, properties, operationType)
    }

    // Complete active transition immediately
    function completeAnimation() {
        _reset()

        if (busy) {
            if (slideAnimation.target) {
                slideAnimation.complete()
                slideAnimation.target.resetPending(true)
            }
            if (fadeAnimation.target) {
                fadeAnimation.complete()
                fadeAnimation.target.resetPending(true)
            }
        }
    }

    function _normalizeOperationType(input) {
        if (input === undefined) {
            input = PageStackAction.Animated
        } else if (typeof(input) === 'boolean') {
            // Temporary support to provide backward compatibility for 'immediate' arguments:
            input = input ? PageStackAction.Immediate : PageStackAction.Animated
        } else if (typeof(input) !== 'number') {
            console.log('Warning: invalid operationType: ' + input + ' ' + typeof(input))
        }
        return input
    }

    function _calculateDuration(destination, location, transitionLength) {
        var distance = (destination - location)
        if (distance == 0) {
            return 1
        }
        var duration = _transitionDuration
        return duration * Math.abs(distance) / (currentPage && currentPage.isLandscape
                                                ? transitionLength
                                                : (transitionLength + _currentWidth) / 2)
    }

    function _reset() {
        if (snapBackAnimation.running) {
            snapBackAnimation.complete()
        }
        snapBackAnimation.clearTarget(true)
        dragBinding.clearTarget()
    }

    function _pushTransition(container, oldContainer, pushProperties) {
        var rv = undefined
        var operationType = pushProperties.operationType
        var replace = pushProperties.replace

        _reset()
        container.show()

        if (!oldContainer) {
            operationType = PageStackAction.Immediate
        } else {
            oldContainer.expired = replace
        }

        if (operationType == PageStackAction.Immediate) {
            // The caller should apply this state change after completing any internal state modification
            rv = (function() {
                container.enterImmediate()
                if (oldContainer) {
                    oldContainer.exitImmediate()
                }
            })
        } else {
            container.pushEnter(oldContainer, operationType, pushProperties.useAnimator)
            if (oldContainer) {
                oldContainer.pushExit(container)
            }
        }

        return rv
    }

    function _popTransition(container, oldContainer, expire, operationType) {
        var rv = undefined

        _reset()
        container.show()

        if (!oldContainer) {
            operationType = PageStackAction.Immediate
        } else {
            oldContainer.expired = expire
        }

        if (operationType == PageStackAction.Immediate) {
            // The caller should apply this state change after completing any internal state modification
            rv = (function() {
                container.enterImmediate()
                if (oldContainer) {
                    oldContainer.exitImmediate()
                }
            })
        } else {
            container.popEnter(oldContainer)
            if (oldContainer) {
                oldContainer.popExit(container)
            }
        }

        return rv
    }

    function _indicatorMaxOpacity() {
        if (!root.currentPage || root.currentPage.showNavigationIndicator == false)
            return 0.0
        // When a pull down menu is active (and intersects the indicator), reduce the opacity of the indicator
        if (_activePullDownMenu && _pageStackIndicator && _pageStackIndicator.enabled) {
            var menuPosition = _activePullDownMenu.mapToItem(root.currentPage, 0, _activePullDownMenu.height)
            var indicatorExtent = _pageStackIndicator.mapToItem(root.currentPage,
                                                                _pageStackIndicator.width,
                                                                _pageStackIndicator.height)
            return (menuPosition.x < indicatorExtent.x) && (menuPosition.y < indicatorExtent.y) ? 0.0 : 1.0
        }
        return 1.0
    }

    property int dragDirection: PageNavigation.NoDirection
    onDragDirectionChanged: {
        if (_currentContainer && (_currentContainer.navigation == PageNavigation.NoNavigation)) {
            if (dragDirection === PageNavigation.Right) {
                _currentContainer.navigationPending = PageNavigation.Forward
            } else if (dragDirection === PageNavigation.NoDirection) {
                _currentContainer.navigationPending = PageNavigation.NoNavigation
            } else {
                _currentContainer.navigationPending = PageNavigation.Back
            }
        }
    }

    property bool dragInvalidated
    onDragInvalidatedChanged: {
        if (dragInvalidated) {
            snapBackAnimation.clearTarget(true)
            updatePeekContainer()
        }
    }

    Binding {
        target: root
        property: 'dragInvalidated'
        when: dragDirection === PageNavigation.Right
        value: _leftFlickDifference > 0
    }
    Binding {
        target: root
        property: 'dragInvalidated'
        when: dragDirection === PageNavigation.Left
        value: _rightFlickDifference > 0
    }
    Binding {
        target: root
        property: 'dragInvalidated'
        when: dragDirection === PageNavigation.Up
        value: _downFlickDifference > 0
    }
    Binding {
        target: root
        property: 'dragInvalidated'
        when: dragDirection === PageNavigation.Down
        value: _upFlickDifference > 0
    }

    function updatePeekContainer() {
        var peekContainer
        var push = true
        if (_rightFlickDifference > 0) {
            dragDirection = PageNavigation.Right
            if (_currentContainer.attachedContainer) {
                peekContainer = _currentContainer.attachedContainer
                // This is always push
            } else if (_pendingContainer) {
                peekContainer = _pendingContainer
                push = peekContainer.pageStackIndex === -1
                        || peekContainer.pageStackIndex > _currentContainer.pageStackIndex
            }
        } else if (_leftFlickDifference > 0) {
            dragDirection = PageNavigation.Left
            push = false
        } else if (_upFlickDifference > 0) {
            dragDirection = PageNavigation.Up
            push = false
        } else if (_downFlickDifference > 0) {
            dragDirection = PageNavigation.Down
            push = false
        }

        flash.opacity = 0.0
        dragInvalidated = false

        if (!peekContainer) {
            peekContainer = PageStack.containerBelow(_currentContainer)
            push = false
        }

        if (peekContainer) {
            snapBackAnimation.setTarget(_currentContainer, peekContainer)

            // Is the peek container able to slide in when the current container is dragged?
            if (peekContainer.testSlideTransition(peekContainer.transitionPartner, push)) {
                peekContainer.opacity = 1.0
            } else {
                peekContainer.opacity = 0.0
            }
        }
    }

    readonly property bool dragInProgress: (_leftFlickDifference > 0)
                                           || (_rightFlickDifference > 0)
                                           || (_upFlickDifference > 0)
                                           || (_downFlickDifference > 0)

    onDragInProgressChanged: {
        if (dragInProgress) {
            updatePeekContainer()
        }
    }

    function _createPageIndicator() {
        if (!_pageStackIndicator) {
            var pageStackIndicatorComponent = Qt.createComponent("private/PageStackIndicator.qml")
            if (pageStackIndicatorComponent.status === Component.Ready) {
                _pageStackIndicator
                        = pageStackIndicatorComponent.createObject(__silica_applicationwindow_instance.indicatorParentItem)
            } else {
                console.log(pageStackIndicatorComponent.errorString())
                return
            }
        }
    }

    onBackNavigationChanged: {
        if (backNavigation) {
            _createPageIndicator()
        }
    }

    onForwardNavigationChanged: {
        if (forwardNavigation) {
            _createPageIndicator()
        }
    }

    property Item _incompleteSnapbackAnimationTarget
    property alias _snapBackAnimation: snapBackAnimation

    onPressed: {
        if (!busy && _currentContainer && _currentContainer.page) {
            if (snapBackAnimation.running) {
                _incompleteSnapbackAnimationTarget = snapBackAnimation.target
                // stop existing snap back animation
                snapBackAnimation.stop()
                snapBackAnimation.clearTarget(false)
            }

            // start dragging
            dragBinding.setTarget(_currentContainer)
        }
    }

    onReleased: {
        var pageChanged = dragBinding.targetItem !== _currentContainer

        dragBinding.clearTarget()

        if (!pageChanged) {
            // activate navigation if the page has been dragged far enough
            if (_rightFlickDifference > _flickThreshold) {
                navigateForward(PageStackAction.Animated)
            } else if (_leftFlickDifference > _flickThreshold) {
                navigateBack(PageStackAction.Animated, PageNavigation.Left)
            } else if (_upFlickDifference > _flickThreshold) {
                navigateBack(PageStackAction.Animated, PageNavigation.Up)
            } else if (_downFlickDifference > _flickThreshold) {
                navigateBack(PageStackAction.Animated, PageNavigation.Down)
            } else {
                if (!snapBackAnimation.target && _incompleteSnapbackAnimationTarget
                        && _incompleteSnapbackAnimationTarget == _currentContainer) {
                    snapBackAnimation.target = _incompleteSnapbackAnimationTarget
                }

                // otherwise slide the page back to normal position
                if (_currentContainer == snapBackAnimation.target) {
                    snapBackAnimation.duration = _calculateDuration(0, _currentContainer.dragOffset,
                                                                    _currentContainer.transitionLength)
                    snapBackAnimation.restart()
                }
            }
        }
        _incompleteSnapbackAnimationTarget = null

        // Remove the flash if present
        flash.opacity = 0.0
        dragDirection = PageNavigation.NoDirection
    }

    onCanceled: {
        dragBinding.clearTarget()

        // slide the page back to normal position
        if (_currentContainer == snapBackAnimation.target) {
            snapBackAnimation.duration = _calculateDuration(0, _currentContainer.dragOffset,
                                                            _currentContainer.transitionLength)
            snapBackAnimation.restart()
        }

        // Remove the flash if present
        flash.opacity = 0.0
        dragDirection = PageNavigation.NoDirection
    }

    Rectangle {
        id: flash

        anchors.fill: parent
        color: root.palette.primaryColor
        opacity: 0
        visible: opacity > 0

        function flashPage() {
            opacity = Theme.opacityLow
            opacity = 0.0
        }

        Behavior on opacity {
            enabled: flash.visible
            FadeAnimation { duration: 400 }
        }
    }

    Binding {
        target: flash
        property: "opacity"
        when: root.pressed && _rightFlickDifference > 0 && _preventForwardNavigation
        value: 0.3
    }

    Binding {
        id: dragBinding

        property Item targetItem
        property real offset

        target: targetItem
        when: root.pressed
        property: "dragOffset"

        value: {
            if (root.horizontalNavigationStyle) {
                // If we can't navigate forward, only allow the page to be dragged slightly
                return offset + root._leftFlickDifference - Math.min(root._rightFlickDifference,
                                                                     (_preventForwardNavigation ? _flickThreshold / 4
                                                                                                : root.width))
            } else {
                return offset + root._upFlickDifference - root._downFlickDifference
            }
        }

        function setTarget(container) {
            offset = container.dragOffset
            targetItem = container
        }

        function clearTarget() {
            targetItem = null
        }
    }

    Binding {
        target: _pageStackIndicator
        property: "maxOpacity"
        value: _indicatorMaxOpacity()
    }

    SequentialAnimation {
        id: fadeAnimation

        property Item target

        function setTarget(container) {
            target = container
            fadeIn.target = container
            fadeOut.target = container.transitionPartner
        }

        function clearTarget(container) {
            if (target === container) {
                target = null
                fadeIn.target = null
                fadeOut.target = null
            }
        }

        PropertyAnimation {
            id: fadeOut

            property: "opacity"
            to: 0.0
            easing.type: Easing.InQuad
            duration: _transitionDuration / 2
        }

        PropertyAnimation {
            id: fadeIn

            property: "opacity"
            to: 1.0
            easing.type: Easing.OutQuad
            duration: _transitionDuration / 2
        }
    }

    PropertyAnimation {
        id: slideAnimation

        property: "dragOffset"
        to: 0.0

        function setTarget(container) {
            target = container
        }

        function clearTarget(container) {
            if (target === container) {
                target = null
            }
        }
    }

    PropertyAnimation {
        id: snapBackAnimation

        to: 0.0
        property: "dragOffset"
        easing.type: Easing.InOutQuad
        onStopped: clearTarget(true)

        function setTarget(container, partner) {
            if (container.transitionPartner && container.transitionPartner != partner) {
                container.transitionPartner.transitionPartner = null
            }
            container.transitionPartner = partner
            partner.transitionPartner = container
            target = container

            // Ensure the page container we will peek at is visible
            partner.show()
        }

        function clearTarget(removeLinks) {
            // hide the page container below after sliding back the current page
            if (target) {
                if (target.transitionPartner && removeLinks) {
                    target.transitionPartner.transitionPartner = null
                    target.transitionPartner.hide()
                    target.transitionPartner.fixDragPosition = false
                    target.transitionPartner = null
                }
                if (target.dragOffset === 0.0) {
                    target.opacity = 1.0
                }
                target = null
            }
        }
    }

    Binding {
        // Block touch input when the page stack is activating a page, or the page is re-orienting
        when: touchBlockTimer.running
              || (currentPage && currentPage.orientationTransitionRunning)
              || dragInProgress
        target: __silica_applicationwindow_instance._touchBlockerItem
        property: "enabled"
        value: true
    }

    Timer {
        // Use a timer to re-enable touch input during animation, or the slow tail-off
        // of the animation will cause some input to be attempted too early
        id: touchBlockTimer
    }

    PageEdgeTransition {
        stack: root
        transitionDuration: _transitionDuration
    }

    Component {
        id: containerComponent

        FocusScope {
            id: container

            property var source
            property var properties
            property var asyncLoad

            property alias asyncObject: asyncStatus
            readonly property Item page: pageLoader.item
                                         ? (pageLoader.item.hasOwnProperty("__silica_page") ? pageLoader.item : null)
                                         : (!!source && source.parent !== undefined ? source : null)
            property Item owner: container
            property int pageStackIndex: -1
            property Item transitionPartner
            property QtObject animation
            property bool expired
            property bool animationRunning: animation ? animation.running || useAnimator : false
            property bool attached
            property Item attachedContainer
            property bool containsDialog: page !== null && page.hasOwnProperty('__silica_dialog')
            property bool fixDragPosition
            property int __silica_pagestack_container
            property int status: PageStatus.Inactive
            property int direction
            property int navigation: PageNavigation.NoNavigation
            property int navigationPending: PageNavigation.NoNavigation
            property bool useAnimator
            readonly property bool soleVisiblePage: direction === PageNavigation.NoDirection
                                                    && status === PageStatus.Active
                                                    && dragOffset === 0
            readonly property bool opaqueBackground: pageLoader.status === Private.AnimatedLoader.Ready
                                                     && pageLoader.item
                                                     && (pageLoader.item._opaqueBackground
                                                         || pageLoader.item.backgroundColor.a === 1)
                                                     && backgroundLoader.status === Private.AnimatedLoader.Ready
                                                     && !backgroundAnimation.running

            property var startTime: new Date().getTime()

            property real transitionDistance: {
                switch (direction) {
                case PageNavigation.Left:
                    return _currentWidth
                case PageNavigation.Right:
                    return -_currentWidth
                case PageNavigation.Up:
                    return _currentHeight
                case PageNavigation.Down:
                    return -_currentHeight
                default:
                    return _currentWidth
                }
            }
            property real transitionLength: Math.abs(transitionDistance)

            property real dragOffset

            x: {
                if (fixDragPosition)
                    return 0

                switch (_currentOrientation) {
                case Orientation.Portrait:
                    return horizontalNavigationStyle ? dragOffset : 0
                case Orientation.PortraitInverted:
                    return horizontalNavigationStyle ? -dragOffset : 0
                case Orientation.Landscape:
                    return horizontalNavigationStyle ? 0 : -dragOffset
                case Orientation.LandscapeInverted:
                    return horizontalNavigationStyle ? 0 : dragOffset
                default:
                    return 0
                }
            }

            y: {
                if (fixDragPosition)
                    return 0

                switch (_currentOrientation) {
                case Orientation.Portrait:
                    return horizontalNavigationStyle ? 0 : dragOffset
                case Orientation.PortraitInverted:
                    return horizontalNavigationStyle ? 0 : -dragOffset
                case Orientation.Landscape:
                    return horizontalNavigationStyle ? dragOffset : 0
                case Orientation.LandscapeInverted:
                    return horizontalNavigationStyle ? -dragOffset : 0
                default:
                    return 0
                }
            }
            width: root.width
            height: root.height
            visible: false

            onVisibleChanged: {
                if (!visible && useAnimator) {
                    useAnimator = false
                    fixDragPosition = true
                }
            }

            Behavior on x {
                enabled: useAnimator && (_currentOrientation == Orientation.Portrait
                                         || _currentOrientation == Orientation.PortraitInverted)
                SequentialAnimation {
                    ParallelAnimation {
                        XAnimator {
                            target: container
                            duration: _transitionDuration
                            easing.type: Easing.InOutQuad
                        }
                        SequentialAnimation {
                            PauseAnimation {
                                duration: 1
                            }
                            ScriptAction {
                                script: {
                                    if (container.asyncLoad && pageLoader.source === loadingComponent) {
                                        container.loadPage()
                                    }
                                }
                            }
                        }
                    }
                    ScriptAction {
                        script: useAnimator = false
                    }
                }
            }

            Behavior on y {
                enabled: useAnimator && (_currentOrientation == Orientation.Landscape
                                         || _currentOrientation == Orientation.LandscapeInverted)
                SequentialAnimation {
                    ParallelAnimation {
                        YAnimator {
                            target: container
                            duration: _transitionDuration
                            easing.type: Easing.InOutQuad
                        }
                        SequentialAnimation {
                            PauseAnimation {
                                duration: 1
                            }
                            ScriptAction {
                                script: {
                                    if (container.asyncLoad && pageLoader.source === loadingComponent) {
                                        container.loadPage()
                                    }
                                }
                            }
                        }
                    }
                    ScriptAction {
                        script: useAnimator = false
                    }
                }
            }

            // This needs to be a binding rather than static assignment so that
            // the value is restored by the Binding element
            opacity: { return 1.0 }

            focus: status === PageStatus.Active && pageLoader.status === Private.AnimatedLoader.Ready

            // Return to the event loop on animation end, because the page status change handler might
            // start another animation, which would then be detected as a binding loop
            onAnimationRunningChanged: if (!animationRunning) animationCompletedTimer.restart()

            function loadPage() {
                var source = container.source

                if (typeof source === "string") {
                    // If 'source' is a string but does not end in .qml, assume it is an
                    // import-path style import (e.g. push(Sailfish.Contacts.Foo))
                    if (source.indexOf(".qml", source.length - ".qml".length) === -1) {
                        source = root.resolveImportPage(source)
                    }
                }

                pageLoader.load(source, "", properties)
            }

            function show() {
                visible = true
            }
            function hide() {
                visible = false
            }
            function removeAnimation() {
                if (animation) {
                    animation.clearTarget(container)
                    animation = null
                }
            }
            function resetPending(noWarnings) {
                // Ensure that we don't have any actions pending
                if (animationCompletedTimer.running) {
                    if (!noWarnings) {
                        console.log('WARNING - previous animation not yet completed!')
                    }
                    animationCompletedTimer.stop()
                    transitionEnded()
                }
            }

            function delayEmitCompleted() {
                completedTimer.start()
            }

            function setStatus(newStatus) {
                if ((navigation !== PageNavigation.NoNavigation)
                        && (status !== newStatus)
                        && (newStatus === PageStatus.Active || newStatus === PageStatus.Activating)) {
                    // If we have previously navigated away from this page, set back to None
                    navigation = PageNavigation.NoNavigation
                    navigationPending = PageNavigation.NoNavigation
                }

                if (newStatus === PageStatus.Active && status === PageStatus.Inactive) {
                    status = PageStatus.Activating
                } else if (newStatus === PageStatus.Inactive && status === PageStatus.Active) {
                    status = PageStatus.Deactivating
                }
                status = newStatus
            }

            function enterImmediate() {
                resetPending()
                opacity = 1.0
                dragOffset = 0
                setStatus(PageStatus.Active)
            }
            function exitImmediate() {
                resetPending()
                hide()
                setStatus(PageStatus.Inactive)
                if (expired) {
                    cleanup()
                }
            }
            function testSlideTransition(partner, push) {
                if (!partner) {
                    return false
                }

                // Don't slide in the page if the partner uses vertical navigation
                var goingForward = pageStackIndex > partner.pageStackIndex
                if (goingForward && !page._horizontalNavigationStyle) {
                    partner.fixDragPosition = true
                } else if (!goingForward && !partner.page._horizontalNavigationStyle) {
                    fixDragPosition = true
                }

                // Use a fade transition we're going to a page that doesn't allow backstepping and
                // the page is not already partially in view
                if (!dragInProgress
                        && ((push && !page.backNavigation)
                            || (!push && !partner.page.backNavigation))
                        && ((push && page._horizontalNavigationStyle)
                            || (!push && partner.page._horizontalNavigationStyle))) {
                    return false
                }

                // Use fade transition if orientation will change
                var nextOrientation = __silica_applicationwindow_instance._selectOrientation(page._allowedOrientations)
                if (partner.page.orientation !== nextOrientation) {
                    if (dragInProgress) {
                        // A drag has been used - continue to use slide transition, but don't move with it
                        fixDragPosition = true
                    } else {
                        return false
                    }
                }
                return true
            }
            function pushEnter(partner, operationType, useAnimator) {
                resetPending()

                direction = page && page.navigationStyle == PageNavigation.Horizontal
                        ? PageNavigation.Right : PageNavigation.Up
                if (testSlideTransition(partner, true)) {
                    var length = (fixDragPosition ? partner.transitionLength : transitionLength)
                    dragOffset = partner.dragOffset + length

                    container.useAnimator = useAnimator
                    partner.useAnimator = useAnimator
                    slideAnimation.duration = !!useAnimator ? 1 : _calculateDuration(0, dragOffset, length)
                    slideAnimation.easing.type = partner.dragOffset === 0 ? Easing.InOutQuad : Easing.OutQuad
                    animation = slideAnimation
                } else {
                    dragOffset = 0
                    opacity = 0.0
                    animation = fadeAnimation
                }

                transitionPartner = partner
                transitionStarted()
            }
            function popEnter(partner) {
                resetPending()
                transitionPartner = partner

                if (transitionPartner.navigation === PageNavigation.NoNavigation) {
                    direction = transitionPartner.page._horizontalNavigationStyle ? PageNavigation.Left : PageNavigation.Up
                } else {
                    direction = transitionPartner.direction
                }

                if (testSlideTransition(transitionPartner, false)) {
                    dragOffset = transitionPartner.dragOffset - transitionDistance

                    slideAnimation.duration = _calculateDuration(0, dragOffset, transitionLength)
                    slideAnimation.easing.type = transitionPartner.dragOffset === 0 ? Easing.InOutQuad : Easing.OutQuad

                    opacity = 1.0
                    animation = slideAnimation
                } else {
                    dragOffset = 0
                    opacity = 0.0
                    animation = fadeAnimation
                }

                transitionStarted()
            }
            function pushExit(partner) {
                resetPending()
                transitionPartner = partner
                direction = PageNavigation.Right
                setStatus(PageStatus.Deactivating)
            }
            function popExit(partner) {
                resetPending()
                transitionPartner = partner
                setStatus(PageStatus.Deactivating)
            }
            function transitionStarted() {
                // Animation runs on the activating page
                setStatus(PageStatus.Activating)

                if (animation) {
                    _ongoingTransitionCount++
                    animation.setTarget(container)

                    animation.restart()

                    // Block touch input until the animation is nearly finished
                    touchBlockTimer.interval = useAnimator ? _transitionDuration : Math.max(animation.duration - 50, 1)
                    touchBlockTimer.restart()
                }
            }
            function transitionEnded() {
                // Ensure that touch input is no longer blocked, even if the timer hasn't expired
                touchBlockTimer.stop()

                if (transitionPartner) {
                    // Clean up the transition partner
                    transitionPartner.transitionPartner = null
                    transitionPartner.transitionEnded()
                    transitionPartner = null
                }

                PageStack.transitionEnded(container)

                if (animation) {
                    removeAnimation()

                    if (_ongoingTransitionCount === 1) {
                        PageStack.allTransitionsEnded()
                    }
                    _ongoingTransitionCount--
                }

                fixDragPosition = false

                direction = PageNavigation.NoDirection

                // if the page hasn't been manually destroyed, visually reparent it back.
                if (page !== null) {
                    if (status === PageStatus.Activating) {
                        setStatus(PageStatus.Active)

                        // Ensure we are fully opaque
                        opacity = 1.0
                    } else if (status === PageStatus.Deactivating) {
                        setStatus(PageStatus.Inactive)
                        hide()
                        if (expired) {
                            cleanup()
                        } else {
                            dragOffset = 0
                        }
                    }
                }
            }
            function cleanup() {
                if (attachedContainer !== null && attachedContainer.pageStackIndex == -1) {
                    attachedContainer.cleanup()
                }
                // if the page hasn't been manually destroyed, visually reparent it back.
                if (page !== null) {
                    page.__stack_container = null

                    if (owner != container) {
                        // container is not the owner of the page - re-parent back to original owner
                        page.parent = owner
                    }
                    page.pageContainer = null
                    page.__stack_container = null
                }
                container.destroy()
            }
            function isPositioned() {
                // If this container is being positioned by an animation or user action
                return (container === dragBinding.targetItem)
                        || (container === slideAnimation.target)
                        || (container === snapBackAnimation.target)
            }

            Binding {
                // When the container is involved in a transition with an animated container
                target: container
                property: "dragOffset"
                when: transitionPartner && transitionPartner.isPositioned()
                value: !transitionPartner
                       ? container.dragOffset
                       : (transitionPartner.dragOffset === 0
                          ? transitionDistance
                          : transitionPartner.dragOffset
                            + (horizontalNavigationStyle ? (transitionPartner.dragOffset < 0 ? _currentWidth
                                                                                             : -_currentWidth)
                                                         : (transitionPartner.dragOffset < 0 ? _currentHeight
                                                                                             : -_currentHeight)))

            }

            // When the container fades out due to vertical pop transition
            property bool verticalPop: dragOffset !== 0
                                       && transitionPartner
                                       && transitionPartner.fixDragPosition
                                       && !page._horizontalNavigationStyle
            Binding {
                target: container
                property: "opacity"
                when: verticalPop
                value: Math.max(0,
                                1.2 - Math.abs(container.dragOffset / (currentPage && currentPage.isPortrait
                                                                       ? Screen.height : Screen.width) * 2.2))
            }
            Connections {
                target: verticalPop && transitionPartner.animation && transitionPartner.animation.running
                        ? container : null
                onOpacityChanged: {
                    if (opacity === 0.0)
                        transitionPartner.animation.complete()
                }
            }

            Binding {
                // When the container is involved in a lateral transition
                target: container
                property: "opacity"
                when: container.dragOffset !== 0
                      && transitionPartner
                      && container.page.rotation !== transitionPartner.page.rotation
                value: transitionPartner
                       ? (!fixDragPosition && (container.status === PageStatus.Activating
                                               || (_currentContainer == transitionPartner
                                                   && container.status !== PageStatus.Deactivating))
                          ? 1.0
                          : 1.0 - Math.abs(container.dragOffset) / (fixDragPosition ? transitionPartner.transitionLength
                                                                                    : transitionLength))
                       : 0
            }

            Timer {
                id: animationCompletedTimer

                interval: 1
                onTriggered: container.transitionEnded()
            }

            QtObject {
                id: asyncStatus

                property int __asyncObject
                property alias __animating: pageLoader.animating

                property string errorString

                property Item page: (pageLoader.status === Private.AnimatedLoader.Ready
                                     || pageLoader.status === Private.AnimatedLoader.Null)
                                    && (container.page && !container.page.hasOwnProperty("__placeholder"))
                                    ? container.page
                                    : null

                signal pageCompleted(Page page)
                signal pageError(string errorString)

                onPageChanged: {
                    if (container.asyncLoad) {
                        pageCompleted(page)
                    }
                }
            }

            Timer {
                id: completedTimer

                interval: 1
                onTriggered: {
                    if (asyncStatus.page) {
                        asyncStatus.pageCompleted(asyncStatus.page)
                    } else {
                        asyncStatus.pageError(asyncStatus.errorString)
                    }
                }
            }

            Private.AnimatedLoader {
                id: backgroundLoader

                width: Screen.width
                height: Screen.height

                source: container.page && !!container.page.background
                        ? container.page.background
                        : undefined

                visible: !container.soleVisiblePage || (container.page && container.page._opaqueBackground)

                onInitializeItem: {
                    item.width = Qt.binding(function() { return backgroundLoader.width })
                    item.height = Qt.binding(function () { return backgroundLoader.height })
                }

                onAnimate: {
                    animating = backgroundAnimation.running

                    if (item) {
                        item.opacity = 0
                        backgroundAnimation.to = 1
                        backgroundAnimation.target = item
                    } else if (replacedItem) {
                        backgroundAnimation.to = 0
                        backgroundAnimation.target = replacedItem
                    }

                    var creationTime = new Date().getTime() - container.startTime
                    var multiplier = Math.max(0.0, Math.min(1.0, creationTime / root._transitionDuration))

                    backgroundAnimation.duration = multiplier * 250

                    backgroundAnimation.restart()

                    animating = Qt.binding(function () { return backgroundAnimation.running })
                }

                FadeAnimator {
                    id: backgroundAnimation

                    duration: 100
                }
            }

            Private.AnimatedLoader {
                id: pageLoader

                width: container.width
                height: container.height

                asynchronous: false

                onError: {
                    source = errorComponent

                    if (container.asyncLoad) {
                        asyncStatus.pageError(errorString)
                    } else {
                        asyncStatus.errorString = errorString

                        completedTimer.start()
                    }
                }

                onAboutToComplete: {
                    if (container.page !== null) {
                        container.asyncLoad = false

                        var page = container.page
                        container.owner = page.parent
                        page.parent = pageLoader

                        for (var prop in container.properties) {
                            if (prop in page) {
                                page[prop] = container.properties[prop]
                            }
                        }

                        initializeItem(page)
                    } else if (container.asyncLoad) {
                        load(loadingComponent)
                    } else {
                        container.loadPage()
                    }
                }

                Component.onCompleted: {
                    if (!container.asyncLoad && asyncStatus.page !== null) {
                        completedTimer.start()
                    }
                }

                onInitializeItem: {
                    if (item.hasOwnProperty("__silica_page")) {
                        item.pageContainer = root
                        item.__stack_container = container

                        item._forwardDestinationChanged.connect(function () {
                            PageStack.forwardDestinationChanged(container)
                        })
                        item._forwardDestinationActionChanged.connect(function () {
                            PageStack.forwardDestinationChanged(container)
                        })
                    }
                }

                animating: loadedAnimation.running

                onAnimate: {
                    if (item) {
                        item.opacity = 0

                        var creationTime = new Date().getTime() - container.startTime
                        var differentOrientation = container.transitionPartner
                                && container.transitionPartner.page.orientation === item.orientation
                        var multiplier = Math.max(0.0, Math.min(1.0, creationTime / root._transitionDuration))

                        pageFadeIn.duration = multiplier * (differentOrientation ? 250 : 400)
                    }

                    loadedAnimation.restart()
                }

                ParallelAnimation {
                    id: loadedAnimation

                    FadeAnimation {
                        target: pageLoader.replacedItem
                        to: 0
                        duration: 100
                    }
                    FadeAnimation {
                        id: pageFadeIn

                        target: pageLoader.item
                        to: 1
                        duration: 250
                    }
                }
            }

            Component {
                id: loadingComponent

                Page {
                    property int __placeholder

                    focus: false

                    PageBusyIndicator {
                        id: busyIndicator

                        running: Qt.application.active
                        z: 1

                        FadeAnimator {
                            target: busyIndicator
                            duration: 1500
                            easing.type: Easing.InExpo
                            to: 1.0
                        }
                    }
                }
            }

            Component {
                id: errorComponent

                Page {
                    property int __placeholder

                    InfoLabel {
                        readonly property Component background: root.pageBackground

                        //% "Page loading failed"
                        text: qsTrId("components-la-page_loading_failed")
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: false
                    }
                }
            }
        }
    }

    function animatorPush() {
        var args = Array.prototype.slice.call(arguments, 0)
        var properties = args[1]
        var pushProperties = _getPushProperties(args)
        pushProperties.useAnimator = true
        return PageStack.push(_getPage(args), properties, pushProperties)
    }

    function animatorReplace() {
        var args = Array.prototype.slice.call(arguments, 0)
        var properties = args[1]
        var pushProperties = _getPushProperties(args)
        pushProperties.replace = true
        pushProperties.useAnimator = true
        return PageStack.push(_getPage(args), properties, pushProperties)
    }

    function animatorReplaceAbove() {
        var args = Array.prototype.slice.call(arguments, 0)
        var existingPage = args.length > 1 ? args.splice(0, 1)[0] : undefined
        if (existingPage === undefined) {
            throw new Error("replaceAbove() called with an undefined existingPage specified")
        }
        var properties = args[1]
        var pushProperties = _getPushProperties(args)
        pushProperties.targetPage = existingPage
        pushProperties.replace = true
        pushProperties.useAnimator = true
        return PageStack.push(_getPage(args), properties, pushProperties)
    }

    // Pops a page off the stack.
    // If page is specified then the stack is unwound to that page; null to unwind the to first page.
    // If the operationType argument is PageStackAction.Immediate then no transition animation is performed.
    // Returns the page instance that was popped off the stack.
    function pop(page, operationType) {
        return PageStack.pop(page, _normalizeOperationType(operationType))
    }

    // Pushes a page on the stack.
    // The page can be defined as a component, item or string.
    // If an item is used then the page will get visually re-parented.
    // If a string is used then it is interpreted as a url that is used to load a page component.
    //
    // The page can also be given as an array of pages. In this case all those pages will be pushed
    // onto the stack. The items in the array can be components, items or strings just like for single
    // pages. Additionally an object can be used, which specifies a page and an optional properties
    // property. This can be used to push multiple pages while still giving each of them properties.
    // When an array is used the transition animation will only be to the last page.
    //
    // The properties argument is optional and allows defining a map of properties to set on the page.
    // If the operationType argument is PageStackAction.Immediate then no transition animation is performed.
    // Returns the page instance.
    function push() {
        var args = Array.prototype.slice.call(arguments, 0)
        var properties = args[1]
        return PageStack.push(_getPage(args), properties, _getPushProperties(args))
    }

    // Replaces a page on the stack.
    // See push() for details.
    function replace() {
        var args = Array.prototype.slice.call(arguments, 0)
        var properties = args[1]
        var pushProperties = _getPushProperties(args)
        pushProperties.replace = true
        return PageStack.push(_getPage(args), properties, pushProperties)
    }

    // Replaces all pages above existingPage with page
    function replaceAbove() {
        var args = Array.prototype.slice.call(arguments, 0)
        var existingPage = args.length > 1 ? args.splice(0, 1)[0] : undefined
        if (existingPage === undefined) {
            throw new Error("replaceAbove() called with an undefined existingPage specified")
        }
        var properties = args[1]
        var pushProperties = _getPushProperties(args)
        pushProperties.targetPage = existingPage
        pushProperties.replace = true
        return PageStack.push(_getPage(args), properties, pushProperties)
    }

    function pushAttached() {
        if (navigationStyle === PageNavigation.Vertical) {
            console.log("Vertical navigation pages don't support attached pages")
            return
        }
        var args = Array.prototype.slice.call(arguments, 0)
        var properties = args[1]
        return PageStack.pushAttached(_getPage(args), properties)
    }

    function _getPage(args) {
        var page = args[0]
        if (typeof page === 'string' && page.search(/\.qml/i) > 0 && page.search(":") < 0 && page.charAt(0) !== '/') {
            var originCallFrame = new Error().stack.split("\n")[2] // (3rd stack frame)...

            // extracts path from: functionName@(url:///path/to/something).qml:lineNumber" (and .js)
            var res = originCallFrame.match(/@(.*)\/.+:-?\d+/)
            if (!res || res.length < 2)
                throw "Unable to load page: '" + page + "'"
            res = res[1]
            page = res + "/" + page
        }
        return page
    }

    function _getPushProperties(args) {
        return {
            operationType: args.length > 2 ? args[2] : PageStackAction.Animated,
            replace: false,
            useAnimator: false,
            targetPage: undefined
        }
    }
}
