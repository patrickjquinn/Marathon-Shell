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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) DialogHeader.qml
// Modified by Shipwright for Qt 6: reads of pageStack._pageStackIndicator go through _keelIndicator (null until the indicator exists, or without a page stack).
// Modified by Shipwright for Qt 6: `dialog` is bound to _findDialog() so that bindings do not read null at creation.
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (4 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"
import "private/Util.js" as Util
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below

BackgroundItem {
    id: dialogHeader

    // Modified by Shipwright for Qt 6: found at creation, not only in Component.onCompleted (bindings below read it first)
    property Item dialog: _findDialog()
    property Flickable flickable
    property string acceptText: defaultAcceptText
    property string cancelText: defaultCancelText
    property alias title: titleText.text
    property bool acceptTextVisible: acceptText.length > 0 && acceptLabel.visible
    property alias extraContent: extraContentPlaceholder
    property bool reserveExtraContent: extraContentPlaceholder.children.length > 0
    property real spacing: Theme.paddingLarge
    property real leftMargin: Theme.horizontalPageMargin
    property real rightMargin: Theme.horizontalPageMargin

    default property alias _children: acceptButton.data
    property int _depth: dialog && dialog._depth ? dialog._depth + 2 : 1
    property bool _glassOnly

    property bool _navigatingBack: dialog && dialog._navigationPending === PageNavigation.Back
    property bool _navigatingForward: dialog && dialog._navigationPending === PageNavigation.Forward
    property bool _canGoBack: dialog && dialog.backNavigation && dialog._depth !== 0
    property bool _backgroundVisible: !__silica_applicationwindow_instance._rotating
    property real _maxButtonSize: dialog.width - Theme.itemSizeLarge
    property real _overlayHeight: overlay.height
    // Modified by Shipwright for Qt 6: the page stack indicator, or null before it exists and for a
    // dialog created outside an ApplicationWindow (no `pageStack` in scope)
    readonly property Item _keelIndicator: typeof pageStack !== "undefined" && pageStack
                                           ? pageStack._pageStackIndicator : null

    //% "Accept"
    property string defaultAcceptText: qsTrId("components-he-dialog_accept")

    //% "Cancel"
    property string defaultCancelText: qsTrId("components-he-dialog_cancel")

    // TODO: Remove top-level BackgroundItem, now here for API compatibility
    down: false
    highlighted: false
    highlightedColor: "transparent"

    height: overlay.height + (title.length > 0 ? titleText.height + Theme.paddingMedium : 0) + spacing
    width: parent ? parent.width : KeelSilica.Screen.width

    onFlickableChanged: {
        if (flickable) {
            overlay.parent = flickable.contentItem
        } else {
            overlay.parent = dialogHeader
        }
    }

    Component.onCompleted: {
        if (!dialog)
            dialog = _findDialog()
        if (dialog) {
            dialog._dialogHeader = dialogHeader
        } else {
            console.log("DialogHeader must have a parent Dialog instance")
        }
        if (!flickable)
            flickable = Util.findFlickable(dialogHeader)
    }

    function _findDialog(): var { // Modified by Shipwright for Qt 6: typed
        var r = parent
        while (r && !r.hasOwnProperty('__silica_dialog'))
            r = r.parent
        return r
    }

    Item {
        id: overlay

        z: 9999 // Just below pulley menu
        height: dialogHeader.dialog.isPortrait // Modified by Shipwright for Qt 6: qualified
                ? Math.max(Theme.itemSizeLarge,
                           (dialogHeader.dialog.orientation == Orientation.Portrait) // Modified by Shipwright for Qt 6: qualified
                           ? (KeelSilica.Screen.topCutout.height + Theme.paddingMedium
                              + Math.max(cancelLabel.implicitHeight, acceptLabel.implicitHeight))
                           : 0)
                : Theme.itemSizeSmall
        width: dialogHeader.width
        y: dialogHeader.flickable ? Math.max(dialogHeader.flickable.contentY, dialogHeader.flickable.originY) : 0 // Modified by Shipwright for Qt 6: qualified
        x: dialogHeader.flickable ? dialogHeader.x : 0 // Modified by Shipwright for Qt 6: qualified

        Item {
            visible: dialogHeader._backgroundVisible

            Private.BackgroundRectangle {
                width: overlay.width
                height: overlay.height
                visible: backgroundLoader.status !== Loader.Ready
                color: __silica_applicationwindow_instance._backgroundColor
            }

            Loader {
                id: backgroundLoader

                width: overlay.width
                height: overlay.height

                sourceComponent: dialogHeader.dialog ? dialogHeader.dialog.background : null
            }

            PanelBackground {
                width: overlay.width
                height: overlay.height
                position: Dock.Top
            }
        }

        FontMetrics {
            id: fontMetrics

            property bool smallFont: boundingRect(cancelLabel.text + acceptLabel.text).width
                                     > (dialogHeader.width - dialogHeader.leftMargin - dialogHeader.rightMargin - Theme.paddingMedium)
            font.pixelSize: Theme.fontSizeLarge
        }

        BackgroundItem {
            id: cancelButton

            property real preferredWidth: Math.min(cancelLabel.implicitWidth * (dialogHeader.reserveExtraContent ? 1.0 : cancelLabel.opacity) // Modified by Shipwright for Qt 6: qualified
                                                   + Theme.paddingLarge + Theme.horizontalPageMargin,
                                                   dialogHeader._maxButtonSize) // Modified by Shipwright for Qt 6: qualified
            height: overlay.height
            anchors {
                left: parent.left
                right: dialogHeader.reserveExtraContent ? extraContentPlaceholder.left : acceptButton.left // Modified by Shipwright for Qt 6: qualified
            }
            enabled: dialogHeader.cancelText !== "" // Modified by Shipwright for Qt 6: qualified
            onClicked: dialogHeader.dialog.reject() // Modified by Shipwright for Qt 6: qualified
            // Modified by Shipwright for Qt 6: the page stack indicator may not exist yet (_keelIndicator)
            highlighted: (dialogHeader._keelIndicator && dialogHeader._keelIndicator.backIndicatorDown) || down // Modified by Shipwright for Qt 6: qualified

            Binding {
                when: dialogHeader.dialog.status === PageStatus.Active // Modified by Shipwright for Qt 6: qualified
                target: dialogHeader._keelIndicator // Modified by Shipwright for Qt 6: qualified
                property: "backIndicatorHighlighted"
                // Modified by Shipwright for Qt 6: the page stack indicator may not exist yet (_keelIndicator)
                value: (dialogHeader._keelIndicator && dialogHeader._keelIndicator.backIndicatorDown) || cancelButton.down // Modified by Shipwright for Qt 6: qualified
            }

            Label {
                id: cancelLabel

                text: dialogHeader.cancelText // Modified by Shipwright for Qt 6: qualified
                color: cancelButton.highlighted
                       ? dialogHeader.palette.highlightColor
                       : dialogHeader.palette.primaryColor
                x: dialogHeader.leftMargin
                width: Math.min(dialogHeader.width - acceptButton.width - x - Theme.paddingMedium, implicitWidth)
                font {
                    pixelSize: dialogHeader.dialog.isPortrait && !fontMetrics.smallFont ? Theme.fontSizeLarge : Theme.fontSizeMedium // Modified by Shipwright for Qt 6: qualified
                    family: Theme.fontFamilyHeading
                }
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: dialogHeader.dialog.orientation == Orientation.Portrait // Modified by Shipwright for Qt 6: qualified
                                              ? (KeelSilica.Screen.topCutout.height / 2) : 0
                truncationMode: TruncationMode.Fade
                opacity: dialogHeader._canGoBack && !dialogHeader._navigatingForward ? 1.0 : 0.0 // Modified by Shipwright for Qt 6: qualified
                Behavior on opacity { FadeAnimation { } }
            }
        }

        Item {
            id: extraContentPlaceholder

            x: cancelButton.preferredWidth
            width: dialogHeader.width - cancelButton.preferredWidth - acceptButton.width
            anchors.verticalCenter: parent.verticalCenter
            opacity: dialogHeader._navigatingBack || dialogHeader._navigatingForward ? 0.0 : 1.0
            Behavior on opacity { FadeAnimation { } }
            visible: opacity > 0
        }

        BackgroundItem {
            id: acceptButton

            onClicked: dialogHeader.dialog.accept() // Modified by Shipwright for Qt 6: qualified

            // This tries to fit in both labels, biased toward showing the acceptText if they would overlap.
            // When moving back we reveal as much of the cancel text as we can.
            // Neither button may be larger than _maxButtonSize.
            // If the accept text is longer than dialog.width/2 then we bias toward the accept text.
            // If the cancel text is longer than dialog.width/2 then we try to fit it in without clipping the acceptText
            // If both are less than dialog.width/2 then they both get dialog.width/2
            width: Math.min(dialogHeader._maxButtonSize, // Modified by Shipwright for Qt 6: qualified
                            Math.max(acceptLabel.implicitWidth
                                     * (dialogHeader.reserveExtraContent ? 1.0 : acceptLabel.opacity) // Modified by Shipwright for Qt 6: qualified
                                     + Theme.paddingLarge + Theme.horizontalPageMargin,
                                     Math.min(dialogHeader.reserveExtraContent ? 0 : dialogHeader.dialog.width/2, // Modified by Shipwright for Qt 6: qualified
                                              dialogHeader.dialog.width - cancelButton.preferredWidth))) // Modified by Shipwright for Qt 6: qualified

            height: overlay.height
            anchors.right: parent.right
            enabled: dialogHeader.acceptText !== "" // Modified by Shipwright for Qt 6: qualified
            opacity: !dialogHeader.dialog || dialogHeader.dialog.canAccept ? 1.0 : Theme.opacityLow
            Behavior on opacity { FadeAnimation { } }

            // Modified by Shipwright for Qt 6: the page stack indicator may not exist yet (_keelIndicator)
            highlighted: (dialogHeader._keelIndicator && dialogHeader._keelIndicator.forwardIndicatorDown) || down // Modified by Shipwright for Qt 6: qualified
            Binding {
                when: dialogHeader.dialog.status === PageStatus.Active // Modified by Shipwright for Qt 6: qualified
                target: dialogHeader._keelIndicator // Modified by Shipwright for Qt 6: qualified
                property: "forwardIndicatorHighlighted"
                // Modified by Shipwright for Qt 6: the page stack indicator may not exist yet (_keelIndicator)
                value: (dialogHeader._keelIndicator && dialogHeader._keelIndicator.forwardIndicatorDown) || acceptButton.down // Modified by Shipwright for Qt 6: qualified
            }

            Label {
                id: acceptLabel

                text: dialogHeader.acceptText // Modified by Shipwright for Qt 6: qualified
                color: acceptButton.highlighted
                       ? dialogHeader.palette.highlightColor
                       : dialogHeader.palette.primaryColor
                // Don't allow the label to extend over the page stack indicator
                width: acceptButton.width - Theme.paddingLarge - Theme.horizontalPageMargin
                truncationMode: TruncationMode.Fade
                font {
                    pixelSize: dialogHeader.dialog.isPortrait && !fontMetrics.smallFont ? Theme.fontSizeLarge : Theme.fontSizeMedium // Modified by Shipwright for Qt 6: qualified
                    family: Theme.fontFamilyHeading
                }
                anchors {
                    right: parent.right
                    // |text|pad-large|indicator
                    rightMargin: dialogHeader.rightMargin
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: dialogHeader.dialog.orientation == Orientation.Portrait // Modified by Shipwright for Qt 6: qualified
                                          ? (KeelSilica.Screen.topCutout.height / 2) : 0
                }

                // TODO: remove rich text format once QTBUG-40161 has been solved
                textFormat: Text.RichText
                horizontalAlignment: Qt.AlignRight
                opacity: dialogHeader._navigatingBack ? 0.0 : 1.0
                Behavior on opacity { FadeAnimation { } }
            }
        }
    }

    Label {
        id: titleText

        y: overlay.height + Theme.paddingMedium
        x: dialogHeader.leftMargin // Modified by Shipwright for Qt 6: qualified
        width: parent.width - dialogHeader.leftMargin - dialogHeader.rightMargin // Modified by Shipwright for Qt 6: qualified
        font.pixelSize: Theme.fontSizeExtraLarge
        wrapMode: Text.Wrap
        color: dialogHeader.palette.highlightColor
        opacity: text.length > 0 ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { } }
    }

    // for testing
    function _headerText(): var { // Modified by Shipwright for Qt 6: typed
        return acceptLabel.text
    }
    function _titleText(): var { // Modified by Shipwright for Qt 6: typed
        return titleText.text
    }
}
