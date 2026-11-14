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
import ".."

SilicaItem {
    id: indicators

    property real itemWidth: Theme.pageStackIndicatorWidth
    property real maxOpacity: root.opacity
    property bool animatingPosition
    property real leftWidth: itemWidth/2
    readonly property bool backIndicatorDown: backMouseArea.pressed && backMouseArea.containsMouse
    property bool backIndicatorHighlighted: backIndicatorDown
    readonly property bool forwardIndicatorDown: forwardMouseArea.pressed && forwardMouseArea.containsMouse
    property bool forwardIndicatorHighlighted: forwardIndicatorDown
    property bool clickablePageIndicators: root.currentPage ? root.currentPage._clickablePageIndicators : true

    opacity: enabled ? Math.min(maxOpacity, root.opacity) : 0.0
    Behavior on opacity { FadeAnimation {} }

    height: !root.currentPage || root.currentPage.isPortrait ? Theme.itemSizeLarge : Theme.itemSizeSmall
    width: pageStack.verticalOrientation ? parent.width : parent.height

    property int currentNavigation: PageNavigation.NoNavigation
    property real currentLateralOffset: root._currentContainer && root._currentContainer.horizontalNavigationStyle
                                        ? root._currentContainer.dragOffset : 0
    property bool busy: root.busy
    onBusyChanged: {
        if (!busy) {
            currentNavigation = PageNavigation.NoNavigation
            partnerPageIndicator.x = -itemWidth/2
        }
    }

    onCurrentLateralOffsetChanged: {
        if (currentLateralOffset < 0) {
            currentNavigation = PageNavigation.Forward
        } else if (currentLateralOffset > 0) {
            currentNavigation = PageNavigation.Back
        } else {
            currentNavigation = PageNavigation.NoNavigation
        }
    }

    Item {
        id: partnerPageIndicator

        property Item container: root._currentContainer ? root._currentContainer.transitionPartner : null
        property bool forwardNavigation: container && (container.page && container.page.forwardNavigation
                                                       || container.attachedContainer)
        property bool canNavigateForward: container && (container.page && container.page.canNavigateForward
                                                        || container.attachedContainer)
        property bool backNavigation: container && container.page && container.page.backNavigation
                                      && container.page._horizontalNavigationStyle && container.pageStackIndex !== 0
        property real lateralOffset: container && container.horizontalNavigationStyle ? container.dragOffset : 0

        onLateralOffsetChanged: {
            if (currentNavigation == PageNavigation.Forward) {
                x = lateralOffset-itemWidth / 2 + indicators.width
            } else if (currentNavigation == PageNavigation.Back) {
                x = lateralOffset-itemWidth / 2
            } else {
                x = -itemWidth/2
            }
        }

        height: indicators.height
        width: itemWidth

        visible: container && container.visible
        opacity: backNavigation && horizontalNavigationStyle && currentNavigation == PageNavigation.Back
                 ? 1.0
                 : (forwardNavigation && currentNavigation == PageNavigation.Forward
                    ? (canNavigateForward ? 1.0 : Theme.opacityHigh)
                    : 0.0)

        PageStackGlassIndicator { }
    }

    Item {
        id: backPageIndicator

        property Item container: root._currentContainer
        property bool backNavigation: container && container.page
                                      && container.page.backNavigation && container.page._horizontalNavigationStyle
                                      && container.pageStackIndex !== 0

        x: currentLateralOffset - itemWidth/2
        height: indicators.height
        width: itemWidth

        visible: backNavigation
        // fade out as we approach the right edge
        opacity: partnerPageIndicator.forwardNavigation
                 ? (partnerPageIndicator.canNavigateForward ? 1.0 : Theme.opacityHigh)
                 : (container ? Math.min((indicators.width - currentLateralOffset) / (indicators.width / 4), 1.0)
                              : 0.0)

        MouseArea {
            id: backMouseArea

            height: parent.height
            width: Theme.itemSizeSmall
            enabled: indicators.clickablePageIndicators && indicators.maxOpacity > 0.0
            x: parent.width/2
            onClicked: root.navigateBack()
        }

        PageStackGlassIndicator {
            opacity: indicators.clickablePageIndicators ? 1.0 : Theme.opacityHigh
            color: backIndicatorHighlighted ? palette.highlightColor : Theme.lightPrimaryColor
        }
    }

    Item {
        id: forwardPageIndicator

        property Item container: root._currentContainer
        property bool forwardNavigation: container && container.page && container.page.forwardNavigation
        property bool canNavigateForward: container && container.page && container.page.canNavigateForward

        function updateOpacity() {
            // if back navigation is not availble in transitionPartner, then fade out as we near the left edge
            var backNavOpacity = partnerPageIndicator.backNavigation
                    ? 1.0 : Math.min(1.0, (currentLateralOffset + indicators.width) / (indicators.width / 4))
            backNavOpacity *= canNavigateForward ? 1.0 : Theme.opacityHigh

            if (currentLateralOffset == 0.0 && !root.busy) {
                fadeAnim.to = container && forwardNavigation ? backNavOpacity : 0.0
                fadeAnim.restart()
            } else {
                fadeAnim.stop()
                opacity = container && forwardNavigation ? backNavOpacity : 0.0
            }
        }

        x: currentLateralOffset + indicators.width - itemWidth/2
        height: indicators.height
        width: itemWidth
        opacity: 0.0
        visible: container && container.visible

        onContainerChanged: updateOpacity()
        onForwardNavigationChanged: updateOpacity()
        onCanNavigateForwardChanged: updateOpacity()
        onXChanged: updateOpacity()

        MouseArea {
            id: forwardMouseArea

            enabled: forwardPageIndicator.canNavigateForward && indicators.clickablePageIndicators && indicators.maxOpacity > 0.0
            height: parent.height
            width: Theme.itemSizeSmall
            anchors.right: parent.horizontalCenter
            onClicked: root.navigateForward()
        }

        FadeAnimation {
            id: fadeAnim

            target: forwardPageIndicator
        }

        PageStackGlassIndicator {
            opacity: indicators.clickablePageIndicators ? 1.0 : Theme.opacityHigh
            color: forwardIndicatorHighlighted ? palette.highlightColor : Theme.lightPrimaryColor
        }
    }

    // Map the indicator onto the page - we can't have the page as the parent, because we must remain opaque when the page is faded
    property Item _page: root.currentPage
    transform: [ Rotation {
        angle: _page ? _page.rotation : 0
    }, Translate {
        x: (_page && (_page.orientation == Orientation.Landscape
                      || _page.orientation == Orientation.PortraitInverted))
           ? root._effectiveWidth : 0
        y: (_page && (_page.orientation == Orientation.PortraitInverted
                      || _page.orientation == Orientation.LandscapeInverted))
           ? root._effectiveHeight : 0
    } ]

    // For testing
    function _forwardPageIndicator() {
        return forwardPageIndicator
    }

    function _backPageIndicator() {
        return backPageIndicator
    }
}
