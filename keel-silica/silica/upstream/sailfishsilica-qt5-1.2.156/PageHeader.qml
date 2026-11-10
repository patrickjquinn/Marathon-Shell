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
import "private/Util.js" as Util

SilicaControl {
    id: pageHeader

    property alias title: headerText.text
    property alias _titleItem: headerText
    property alias wrapMode: headerText.wrapMode
    property alias extraContent: extraContentPlaceholder
    property string description
    property int descriptionWrapMode: Text.NoWrap
    property Item page
    property alias titleColor: headerText.color
    property real leftMargin: Theme.horizontalPageMargin
    property real rightMargin: Theme.horizontalPageMargin
    property real descriptionRightMargin: rightMargin
    property real topMargin: Math.max(_minimumTopMargin,
                                      Math.floor((_preferredHeight - metrics.height) / 2))
    readonly property real titleHeight: headerText.height

    property bool interactive: enabled && page && page.canNavigateForward
    readonly property bool defaultHighlighted: interactive
                                               && ((_navigateForwardMouseArea
                                                    && _navigateForwardMouseArea.containsMouse)
                                                   || (pageStack._pageStackIndicator
                                                       && pageStack._pageStackIndicator.forwardIndicatorDown))

    property Item _descriptionLabel
    property real _preferredHeight: page && page.isLandscape ? Theme.itemSizeSmall : Theme.itemSizeLarge
    property Item _navigateForwardMouseArea
    property int _minimumTopMargin: (page && page.orientation == Orientation.Portrait)
                                    ? Screen.topCutout.height : 0

    onDescriptionChanged: {
        if (description.length > 0 && !_descriptionLabel) {
            var component = Qt.createComponent(Qt.resolvedUrl("private/PageHeaderDescription.qml"))
            if (component.status === Component.Ready) {
                _descriptionLabel = component.createObject(pageHeader,
                    { "wrapMode": Qt.binding(function() { return pageHeader.descriptionWrapMode }) })
            } else {
                console.warn("PageHeaderDescription.qml instantiation failed " + component.errorString())
            }
        }
    }

    onInteractiveChanged: {
        if (interactive && !_navigateForwardMouseArea) {
            var component = Qt.createComponent(Qt.resolvedUrl("private/PageHeaderMouseArea.qml"))
            if (component.status === Component.Ready) {
                _navigateForwardMouseArea = component.createObject(pageHeader)
            } else {
                console.warn("PageHeaderMouseArea.qml instantiation failed " + component.errorString())
            }
        }
    }

    Component.onCompleted: {
        if (!page) {
            page = Util.findPage(pageHeader)
        }
    }

    width: parent ? parent.width : Screen.width
    // set height that keeps the first line of text aligned with the page indicator (if no cutout)
    implicitHeight: headerText.y + headerText.height + Theme.paddingMedium
                    + ((_descriptionLabel && description.length > 0) ? _descriptionLabel.height : 0)
    height: Math.max(_preferredHeight, implicitHeight)

    highlighted: defaultHighlighted

    Label {
        id: headerText

        // Don't allow the label to extend over the page stack indicator
        width: Math.min(implicitWidth, parent.width - leftMargin - rightMargin)
        truncationMode: TruncationMode.Fade

        // color should indicate if interactive
        color: interactive
               ? (highlighted ? palette.highlightColor : palette.primaryColor)
               : (highlighted ? palette.primaryColor : palette.highlightColor)

        // align first line with page indicator (if no cutout)
        y: pageHeader.topMargin
        anchors {
            right: parent.right
            rightMargin: pageHeader.rightMargin
        }
        font {
            pixelSize: Theme.fontSizeLarge
            family: Theme.fontFamilyHeading
        }

        TextMetrics {
            id: metrics

            font: headerText.font
            text: "X"
        }
    }

    Item {
        id: extraContentPlaceholder

        // Extend extraContent to the full area to the left of the title.
        anchors {
            left: parent.left
            leftMargin: pageHeader.leftMargin
            right: headerText.left
            top: parent.top
            bottom: parent.bottom
        }
    }
}
