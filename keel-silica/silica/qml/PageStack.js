// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Joona Petrell <joona.petrell@jollamobile.com>
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) PageStack.js

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

// Page stack. Items are page containers.
var pageStack = []

var placeholderPageCache = null

var pendingAction
var pendingReplaceAboveTarget
var targetContainer

var inProgress

function modifyPageStack(operation, callback) {
    if (inProgress) {
        // Don't allow another modification to begin while another has not yet finished
        throw new Error("Cannot " + operation + " while operation is in progress: " + inProgress)
    }

    var rv
    inProgress = operation

    try {
        var result = callback()
        inProgress = undefined

        if (result) {
            if ('rv' in result) {
                rv = result.rv
            }
            if (('stateChange' in result) && (result.stateChange !== undefined)) {
                // Apply any state change resulting from the function
                result.stateChange()
            }
        }
    } catch (exception) {
        inProgress = undefined
        console.warn("Error while modifying page stack:", exception)
        throw exception
    }

    return rv
}


// Pushes a page on the stack.
function push(page, properties, pushProperties) {
    return modifyPageStack('push', function() { return doPush(page, properties, pushProperties) })
}

function doPush(page, properties, pushProperties) {
    var replace = pushProperties.replace
    var operationType = pushProperties.operationType
    // page order sanity check
    if ((!replace && page == currentPage)
            || (replace && pageStack.length > 1 && page == pageStack[pageStack.length - 2].page)) {
        throw new Error("Cannot navigate so that the resulting page stack has two consecutive entries of the same page instance.")
    }

    // if we're expected to transition, then ignore if there's an ongoing transition.
    if (_ongoingTransitionCount > 0) {
        console.log('Warning: cannot push while transition is in progress')
        return ({ 'rv': null })
    }

    var targetPage = pushProperties.targetPage
    if (replace) {
        if (targetPage) {
            var targetIndex = indexOfPage(targetPage)
            if (targetIndex === (pageStack.length - 1)) {
                throw new Error("Cannot replace with target page at the top of the stack")
            } else if (targetIndex < 0) {
                throw new Error("Cannot replace with invalid target page which is not present on the stack")
            }
        } else if (targetPage !== null && _currentContainer && _currentContainer.attached) {
            // make sure there are enough pages in the stack to pop
            if (pageStack.length <= 2) {
                return ({ 'rv': null })
            }
            targetPage = pageStack[_currentContainer.pageStackIndex - 2].page
        }
    } else if (targetPage) {
        console.log('Warning: target page ignored without replace option')
    }

    cancelPending()

    var container = null
    var oldContainer = null

    if (pageStack.length) {
        // get the current container
        oldContainer = _currentContainer

        // pop the old container off the stack if this is a replace
        if (replace) {
            if (operationType !== PageStackAction.Immediate) {
                _previousContainer = oldContainer
            }

            do {
                container = pageStack[pageStack.length - 1]

                if (container === oldContainer) {
                    // This page will be cleaned up after the transition
                    pageStack.pop()
                    container = null
                } else {
                    if (targetPage === undefined || targetPage === container.page) {
                        break
                    }

                    // Otherwise, this page should be cleaned up
                    pageStack.pop()
                    container.pageStackIndex = -1
                    container.cleanup()
                    container = null
                }
            } while (pageStack.length > 0)
        }
    }

    // figure out if more than one page is being pushed
    var pages
    if (page instanceof Array) {
        pages = page
        page = pages.pop()
        if (page.createObject === undefined && page.parent === undefined && typeof page != "string") {
            properties = properties || page.properties
            page = page.page
        }
    }

    // push any extra defined pages onto the stack
    if (pages) {
        var i
        for (i = 0; i < pages.length; i++) {
            var tPage = pages[i]
            var tProps
            if (tPage.createObject === undefined && tPage.parent === undefined && typeof tPage != "string") {
                tProps = tPage.properties
                tPage = tPage.page
            }

            container = initPage(tPage, tProps, false)
            container.pageStackIndex = pageStack.length
            pageStack.push(container)
        }
    }

    // animator-based push will turn into immediate if there is no old container
    var useAnimator = pushProperties.useAnimator
    var canUseAnimator = useAnimator && !!oldContainer && operationType !== PageStackAction.Immediate
    // initialize the page
    container = initPage(page, properties, canUseAnimator)
    container.pageStackIndex = pageStack.length


    // push the page container onto the stack
    pageStack.push(container)
    targetContainer = container

    // Update current before transition
    _currentContainer = targetContainer

    // perform page transition
    var stateChange = root._pushTransition(container, oldContainer, pushProperties)

    depth = pageStack.length

    if (stateChange) {
        // No animated transition is in progress
        prepareDestination(container)
    }

    if (useAnimator) {
        return ({ 'rv': container.asyncObject, 'stateChange': stateChange })
    }

    return ({ 'rv': container.page, 'stateChange': stateChange })
}

function prepareDestination(container) {
    if (container.page && container.page._forwardDestination) {
        var replaceAboveTarget = undefined

        if (!container.page.forwardNavigation) {
            throw new Error("Only Pages with forwardNavigation permit acceptDestination to be set.")
        }

        // is this destination already in the page stack?
        var destinationContainer = find(function(page) {
            return (page === container.page._forwardDestination)
        })

        if (destinationContainer) {
            if (container.page._forwardDestinationAction !== PageStackAction.Pop) {
                throw new Error("Only Pop action can be used with a destination page already in the page stack.")
            }

            // We will pop down to this destination
            _pendingContainer = destinationContainer
        } else {
            if ((container.page._forwardDestinationAction !== PageStackAction.Push)
                    && (container.page._forwardDestinationAction !== PageStackAction.Replace)) {
                throw new Error("Only Push and Replace actions can be used with a destination page not already in the page stack.")
            }

            replaceAboveTarget = container.page._forwardDestinationReplaceTarget
            if (replaceAboveTarget !== undefined) {
                if (container.page._forwardDestinationAction !== PageStackAction.Replace) {
                    throw new Error("Replace target was specified, but acceptDestinationAction is not Replace")
                }
                if (replaceAboveTarget) {
                    var targetIndex = indexOfPage(replaceAboveTarget)
                    if (targetIndex === (pageStack.length - 1)) {
                        throw new Error("Cannot replace with target page at the top of the stack")
                    } else if (targetIndex < 0) {
                        throw new Error("Cannot replace with invalid target page which is not present on the stack")
                    }
                } else if (_currentContainer && _currentContainer.attached) {
                    // make sure there are enough pages in the stack to pop
                    if (pageStack.length <= 2) {
                        throw new Error("Cannot replace the top-most page as the page that owns this attached page is already at the top of the stack")
                    }
                    replaceAboveTarget = pageStack[_currentContainer.pageStackIndex - 2].page
                }
            }

            // initialize the pending page so it can be peeked at
            var _pendingProps = {}
            if (container.page._forwardDestinationProperties !== undefined) {
                _pendingProps = container.page._forwardDestinationProperties
            }

            _pendingContainer = initPage(container.page._forwardDestination, _pendingProps, false)
            if (_pendingContainer) {
                container.page._forwardDestinationInstance = _pendingContainer.page
            }
        }

        pendingAction = container.page._forwardDestinationAction
        pendingReplaceAboveTarget = replaceAboveTarget
    }
}

function pushPending(operationType) {
    return modifyPageStack('pushPending', function() { return doPushPending(operationType) })
}

function doPushPending(operationType) {
    // if we're expected to transition, then ignore if there's an ongoing transition.
    if (_ongoingTransitionCount > 0) {
        console.log('Warning: cannot pushPending while transition is in progress')
        return ({ 'rv': null })
    }

    var container = _pendingContainer
    var action = pendingAction
    var replaceAboveTarget = pendingReplaceAboveTarget

    _pendingContainer = null
    pendingAction = undefined
    pendingReplaceAboveTarget = undefined

    if (action === PageStackAction.Pop) {
        return doPop(container.page, operationType)
    }

    var oldContainer
    if (action === PageStackAction.Replace) {
        // pop the current container off the stack, and replace with pending
        oldContainer = pageStack.pop()
        if (operationType === PageStackAction.Animated) {
            _previousContainer = oldContainer
        }
        if (replaceAboveTarget !== undefined && pageStack.length > 0) {
            do {
                var tempContainer = pageStack[pageStack.length - 1]
                if (replaceAboveTarget !== null && replaceAboveTarget === tempContainer.page) {
                    break
                }
                pageStack.pop()
                tempContainer.pageStackIndex = -1
                tempContainer.cleanup()
            } while (pageStack.length > 0)
        }
    } else {
        // push on top of existing
        oldContainer = _currentContainer
    }

    container.pageStackIndex = pageStack.length
    pageStack.push(container)
    targetContainer = container

    if (operationType === PageStackAction.Immediate) {
        _currentContainer = targetContainer
    }

    // perform page transition
    var stateChange
    if (action === PageStackAction.Replace) {
        stateChange = root._popTransition(container, oldContainer, true, operationType)
    } else {
        var pushProperties = {operationType: operationType, useAnimator: false, replace: false}
        stateChange = root._pushTransition(container, oldContainer, pushProperties)
    }

    depth = pageStack.length

    if (stateChange) {
        // No animated transition is in progress
        prepareDestination(container)
    }

    return ({ 'rv': oldContainer.page, 'stateChange': stateChange })
}

function cancelPending() {
    if (_pendingContainer) {
        if (_currentContainer._forwardDestinationInstance === _pendingContainer.page) {
            _currentContainer._forwardDestinationInstance = null
        }
        if (pendingAction !== PageStackAction.Pop) {
            _pendingContainer.cleanup()
        }
        _pendingContainer = null
        pendingAction = undefined
        pendingReplaceAboveTarget = undefined
    }
}

// Push a page above the current stack top
function pushAttached(page, properties) {
    return modifyPageStack('pushAttached', function() { return doPushAttached(page, properties) })
}

function doPushAttached(page, properties) {
    if (_currentContainer.attachedContainer) {
        _currentContainer.attachedContainer.cleanup()
        _currentContainer.attachedContainer = null
    }
    if (page) {
        var container = initPage(page, properties, false)
        container.attached = true
        _currentContainer.attachedContainer = container

        return ({ 'rv': container.page })
    } else {
        return ({ 'rv': null })
    }
}

// Initializes a page and its container.
function initPage(page, properties, useAnimator) {
    var container = containerComponent.createObject(root, {
        "source": page,
        "properties": properties,
        "asyncLoad": useAnimator
    })

    return container
}

function forwardDestinationChanged(container) {
    if (container === _currentContainer) {
        cancelPending()
        prepareDestination(_currentContainer)
    }
}

function containerAbove(container) {
    for (var i = pageStack.length - 2; i >= 0; --i) {
        if (container === pageStack[i]) {
            return pageStack[i+1]
        }
    }
    return null
}

function containerBelow(container) {
    for (var i = 1; i < pageStack.length; i++) {
        if (container === pageStack[i]) {
            return pageStack[i-1]
        }
    }
    return null
}

function index(container) {
    for (var i = 0; i < pageStack.length; i++) {
        if (container === pageStack[i]) {
            return i
        }
    }
    return -1
}

function containerAt(index) {
    return pageStack[index]
}

function indexOfPage(targetPage) {
    var i = pageStack.length - 1
    for ( ; i >= 0; --i) {
        if (pageStack[i].page === targetPage) {
            return i
        }
    }
    return -1
}

// Pops a page off the stack.
function pop(targetPage, operationType) {
    return modifyPageStack('pop', function() { return doPop(targetPage, operationType) })
}

function doPop(targetPage, operationType) {
    // if we're expected to transition, then ignore if there's an ongoing transition.
    if (_ongoingTransitionCount > 0) {
        console.log('Warning: cannot pop while transition is in progress')
        return ({ 'rv': null })
    }

    cancelPending()

    // make sure there are enough pages in the stack to pop
    if (pageStack.length <= 1) {
        return ({ 'rv': null })
    }

    if (targetPage) {
        var targetIndex = indexOfPage(targetPage)
        if (targetIndex === (pageStack.length - 1)) {
            // Already on target page. Nothing to do.
            return ({ 'rv': null })
        } else if (targetIndex < 0) {
            throw new Error("Cannot pop to invalid target page which is not present on the stack")
        }
    } else if (_currentContainer && _currentContainer.attached) {
        // make sure there are enough pages in the stack to pop
        if (pageStack.length <= 2) {
            return ({ 'rv': null })
        }
        targetPage = pageStack[_currentContainer.pageStackIndex - 2].page
    }

    // pop the current container off the stack and get the next container
    var oldContainer = _currentContainer
    var container = null

    do {
        container = pageStack[pageStack.length - 1]

        if (container === oldContainer) {
            // This page will be cleaned up after the transition
            pageStack.pop()
            container = null
        } else {
            if (!targetPage || targetPage === container.page) {
                break
            }

            // Otherwise, this page should be cleaned up
            pageStack.pop()
            container.pageStackIndex = -1
            // Do not delete if this is the attached page of the target page.
            // (If it's an attached page there must be at least one page left.
            // Attached page always has a "parent page".)
            if (!container.attached || pageStack[pageStack.length - 1].page !== targetPage) {
                container.cleanup()
            }
            container = null
        }
    } while (pageStack.length > 1)

    // We must have at least one page left in the stack
    if (!container) {
        container = pageStack[0]
    }

    targetContainer = container

    // Do not destroy the old page if it was the attached page of the target page.
    var cleanup = container.attachedContainer !== oldContainer

    // perform page transition
    var stateChange = root._popTransition(container, oldContainer, cleanup, operationType)

    if (stateChange) {
        // No animated transition is in progress
        _currentContainer = targetContainer
        depth = pageStack.length

        prepareDestination(container)
    } else {
        // Don't reduce the depth until the animation completes
        depth = pageStack.length
    }

    return ({ 'rv': oldContainer.page, 'stateChange': stateChange })
}

function popAttached(targetPage, operationType) {
    return modifyPageStack('popAttached', function() { return doPopAttached(targetPage, operationType) })
}

function doPopAttached(targetPage, operationType) {
    if (_ongoingTransitionCount > 0) {
        return ({ 'rv': null })
    }

    // make sure there are enough pages in the stack to pop
    if (pageStack.length < 1) {
        return ({ 'rv': null })
    }

    var targetIndex
    if (targetPage) {
        targetIndex = indexOfPage(targetPage)
        if (targetIndex < 0) {
            throw new Error("Cannot popAttached to invalid target page which is not present on the stack")
        }
    } else {
        if (pageStack[pageStack.length - 1].attached) {
            targetIndex = pageStack.length - 2
        } else {
            targetIndex = pageStack.length - 1
        }
    }

    var container = pageStack[targetIndex]
    if (!container.attachedContainer) {
        throw new Error("No attached page to pop")
    }

    if (container.attachedContainer.pageStackIndex < 0) {
        // Popping a page that's not yet in stack
        container.attachedContainer.cleanup()
        container.attachedContainer = null
        return ({ 'rv': null })
    } else if (container.attachedContainer.pageStackIndex !== pageStack.length - 1) {
        throw new Error("Cannot popAttached including pages which are not attached")
    }

    // pop the current container off the stack and get the next container
    var oldContainer = container.attachedContainer

    pageStack.pop()
    depth = pageStack.length

    if (container.attachedContainer !== _currentContainer) {
        // This pop does not affect the visual state of the page stack
        container.attachedContainer.cleanup()
        container.attachedContainer = null
        depth = pageStack.length
        return ({ 'rv': null })
    } else {
        // This page will be cleaned up after the transition
        container.attachedContainer = null
    }

    targetContainer = container

    // perform page transition
    var stateChange = root._popTransition(container, oldContainer, true, operationType)

    if (stateChange) {
        // No animated transition is in progress
        _currentContainer = targetContainer
        prepareDestination(container)
    }

    return ({ 'rv': oldContainer.page, 'stateChange': stateChange })
}

// Clears the page stack.
function clear() {
    return modifyPageStack('clear', function() { return doClear() })
}

function doClear() {
    cancelPending()
    var container
    while (container = pageStack.pop()) {
        container.pageStackIndex = -1
        container.cleanup()
    }
    depth = 0
    _currentContainer = null
    targetContainer = null
}

// Iterates through all pages in the stack (top to bottom) to find a page.
function find(func) {
    for (var i = pageStack.length - 1; i >= 0; i--) {
        var page = pageStack[i].page
        if (func(page)) {
            return pageStack[i]
        }
    }
    return null
}

function transitionEnded(container) {
    if (_previousContainer && (container === _previousContainer)) {
        _previousContainer.pageStackIndex = -1
        _previousContainer = null
    }

    if (container.pageStackIndex === -1) {
        if (container === _currentContainer) {
            // Don't make the current container become null
            if (targetContainer) {
                _currentContainer = targetContainer
                targetContainer = null
            } else {
                _currentContainer = pageStack[pageStack.length - 1]
            }
        }
    }
}

function allTransitionsEnded() {
    if (targetContainer) {
        _currentContainer = targetContainer
        targetContainer = null
    }

    depth = pageStack.length

    if (_currentContainer && !_pendingContainer) {
        prepareDestination(_currentContainer)
    }

    // This is causing trouble:
    //gc()
}


function enterAttached(container, operationType) {
    return modifyPageStack('enterAttached', function() { return doEnterAttached(container, operationType) })
}

function doEnterAttached(container, operationType) {
    if (_ongoingTransitionCount > 0) {
        console.log('Warning: cannot enterAttached while transition is in progress')
        return ({ 'rv': null })
    }

    var oldContainer = _currentContainer
    container.pageStackIndex = pageStack.length

    // push the page container onto the stack
    pageStack.push(container)
    depth = pageStack.length

    _currentContainer = container
    targetContainer = container

    var pushProperties = {
        operationType: operationType,
        useAnimator: false,
        replace: false
    }

    var stateChange = root._pushTransition(container, oldContainer, pushProperties)
    if (stateChange) {
        // No animated transition is in progress
        prepareDestination(container)
    }
    return ({ 'rv': oldContainer.page, 'stateChange': stateChange })
}

function exitAttached(operationType) {
    return modifyPageStack('exitAttached', function() { return doExitAttached(operationType) })
}

function doExitAttached(operationType) {
    if (_ongoingTransitionCount > 0) {
        console.log('Warning: cannot exitAttached while transition is in progress')
        return ({ 'rv': null })
    }

    var oldContainer = _currentContainer
    var container = pageStack[_currentContainer.pageStackIndex - 1]

    // pop the attached page container from the stack
    pageStack.pop()
    oldContainer.pageStackIndex = -1
    depth = pageStack.length

    _currentContainer = container
    targetContainer = container

    var stateChange = root._popTransition(container, oldContainer, false, operationType)
    if (stateChange) {
        // No animated transition is in progress
        prepareDestination(container)
    }
    return ({ 'rv': oldContainer.page, 'stateChange': stateChange })
}
