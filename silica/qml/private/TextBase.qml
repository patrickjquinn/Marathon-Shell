// SPDX-FileCopyrightText: 2013-2018 Jolla Ltd
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2013-2018 Jolla Ltd.
** Copyright (C) 2020 Open Mobile Platform LLC.
**
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/TextBase.qml
// Modified by Shipwright for Qt 6: optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are.
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places).
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (3 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: the editor regaining active focus stops focusLossTimer, so a loss and refocus within its 1 ms interval no longer clears focus a moment later (lost keystrokes)
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour).

/*

With labelVisible: true (default)

  -------------------------
  |                       |
  |     textTopMargin     |
  |                       |
  | - - - - - - - - - - - |
  |                       |
  |                       |
  |      contentItem      |
  |                       |
  |                       |
  ------------------------- background rule
  |  Theme.paddingSmall   |
  | - - - - - - - - - - - |
  |                       |
  |       labelItem       |
  |                       |
  | - - - - - - - - - - - |
  |  Theme.paddingSmall   |
  -------------------------


With labelVisible: false

  -------------------------
  |                       |
  |     textTopMargin     |
  |                       |
  | - - - - - - - - - - - |
  |                       |
  |                       |
  |                       |
  |     contentItem       |
  |                       |
  |                       |
  |                       |
  ------------------------- background rule
  |  Theme.paddingSmall   |
  | - - - - - - - - - - - |
  |  Theme.paddingSmall   |
  -------------------------

*/

pragma ComponentBehavior: Bound // Modified by Shipwright for Qt 6: ids of outer objects used in inner components
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "Util.js" as Util
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below
import Sailfish.Silica.private 1.0 as KeelPrivate // Modified by Shipwright for Qt 6: Util._keelOptionalObject

TextBaseItem {
    id: textBase

    property string label
    property color color: textBase.highlighted ? palette.highlightColor : palette.primaryColor

    property color cursorColor: palette.primaryColor
    property alias placeholderText: placeholderTextLabel.text
    property alias placeholderColor: placeholderTextLabel.color

    property string description

    // internal
    property alias placeholderAnimationEnabled: placeholderBehavior.enabled
    property bool softwareInputPanelEnabled: true
    property bool errorHighlight: false
    // margins indicate the area around filled or underlined editor area
    property real textMargin: Theme.horizontalPageMargin
    property real textLeftMargin: textMargin + (leftItemContainer.active ? leftItemContainer.width + Theme.paddingMedium : 0)
    property real textRightMargin: textMargin

    property real textTopMargin: Theme.paddingSmall
    // paddings indicate how much space there is around text to the filled or underlined area
    property real textTopPadding: _filled ? Theme.paddingMedium : 0
    property real textLeftPadding: _filled ? Theme.paddingMedium : 0
    // note: not applied to rightItem.
    // if it's interactive, it can make sense to cover all the area to the end of the underline
    property real textRightPadding: _filled ? Theme.paddingMedium : 0

    // TODO: Change to use "placeholderTextLabel.lineHeight once merge request #298 is merged.
    readonly property real textVerticalCenterOffset: _totalTopMargins + placeholderTextLabel.height / 2
    property int selectionMode: TextInput.SelectCharacters
    property alias font: placeholderTextLabel.font
    property int focusOutBehavior: FocusBehavior.ClearItemFocus
    property bool autoScrollEnabled: true
    property int backgroundStyle: TextEditor.UnderlineBackground

    property Component background: Rectangle {
        x: textBase.textLeftMargin // Modified by Shipwright for Qt 6: qualified
        anchors.top: contentContainer.bottom
        width: parent.width - x - textBase.textRightMargin // Modified by Shipwright for Qt 6: qualified
        height: Math.round(Theme.pixelRatio)
        color: Theme.rgba(textBase._colorWithError, Theme.opacityHigh)
        visible: textBase.backgroundStyle != TextEditor.NoBackground // Modified by Shipwright for Qt 6: qualified

        Rectangle {
            id: focusHighlight

            property real focusLevel

            color: textBase._colorWithError
            height: parent.height + (textBase._editor.activeFocus // Modified by Shipwright for Qt 6: qualified
                                     ? Math.round(Theme.pixelRatio) + (palette.colorScheme === Theme.DarkOnLight ? 1 : 0)
                                     : 0)
            width: focusLevel * parent.width
            states: State {
                name: "focused"
                when: textBase._editor.activeFocus // Modified by Shipwright for Qt 6: qualified
                PropertyChanges {
                    target: focusHighlight
                    focusLevel: 1.0
                }
            }
            transitions: Transition {
                to: "focused"
                NumberAnimation { property: "focusLevel"; duration: 150 }
            }
        }

        Rectangle {
            visible: textBase._filled
            anchors.bottom: parent.top
            width: parent.width
            height: contentContainer.height
            color: textBase._editor.activeFocus ? Theme.highlightColor : Theme.primaryColor // Modified by Shipwright for Qt 6: qualified
            opacity: 0.1
        }
    }

    property alias leftItem: leftItemContainer.item
    property alias rightItem: rightItemContainer.item

    // TODO: Remove this wrongly-formulated property name once users have been migrated, and version incremented
    property alias enableSoftwareInputPanel: textBase.softwareInputPanelEnabled

    property bool _suppressPressAndHoldOnText
    property Item _backgroundItem
    readonly property bool _filled: backgroundStyle == TextEditor.FilledBackground
    property QtObject _feedbackEffect
    property var _appWindow: __silica_applicationwindow_instance
    property Item _flickable
    property alias _errorIcon: errorIcon

    property alias _flickableDirection: flickable.flickableDirection
    property rect _autoScrollCursorRect: Qt.rect(0, 0, 0, 0)

    property Item _scopeItem: textBase
    property alias editor: textBase._editor  //XXX Deprecated

    // JB#45671: Deprecate labelVisible
    property bool labelVisible: true
    property bool hideLabelOnEmptyField: true

    property Component labelComponent: defaultLabelComponent

    property Component defaultLabelComponent: Component {
        TextEditorLabel {
            width: parent.width
            editor: textBase
        }
    }

    property Item _labelItem
    readonly property color _colorWithError: textBase.errorHighlight ? palette.errorColor : color

    default property alias _children: contentContainer.data
    property alias contentItem: contentContainer
    property alias _placeholderTextLabel: placeholderTextLabel
    property bool focusOnClick: !readOnly
    property bool _singleLine
    readonly property bool _isEmpty: text.length === 0 && !_editor.inputMethodComposing
    readonly property real _bottomMargin: Theme.paddingSmall
                                          + (labelVisible
                                             ? labelItemContainer.height + labelItemContainer.anchors.bottomMargin
                                             : Theme.paddingSmall)
                                          + descriptionLabel.height

    function forceActiveFocus(): void { _editor.forceActiveFocus() } // Modified by Shipwright for Qt 6: typed
    function cut(): void { _editor.cut() } // Modified by Shipwright for Qt 6: typed
    function copy(): void { _editor.copy() } // Modified by Shipwright for Qt 6: typed
    function paste(): void { _editor.paste() } // Modified by Shipwright for Qt 6: typed
    function select(start: var, end: var): void { _editor.select(start, end) } // Modified by Shipwright for Qt 6: typed
    function selectAll(): void { _editor.selectAll() } // Modified by Shipwright for Qt 6: typed
    function selectWord(): void { _editor.selectWord() } // Modified by Shipwright for Qt 6: typed
    function deselect(): void { _editor.deselect() } // Modified by Shipwright for Qt 6: typed
    function positionAt(mouseX: var, mouseY: var): var { // Modified by Shipwright for Qt 6: typed
        var translatedPos = mapToItem(_editor, mouseX, mouseY)
        return _editor.positionAt(translatedPos.x, translatedPos.y)
    }
    function positionToRectangle(position: var): var { // Modified by Shipwright for Qt 6: typed
        var rect = _editor.positionToRectangle(position)
        var translatedPos = mapFromItem(_editor, rect.x, rect.y)
        rect.x = translatedPos.x
        rect.y = translatedPos.y
        return rect
    }

    function _fixupScrollPosition(): void { // Modified by Shipwright for Qt 6: typed
        scrollProxy.HorizontalAutoScroll.fixup()
        scrollProxy.VerticalAutoScroll.fixup()
        VerticalAutoScroll.fixup()
    }

    onHorizontalAlignmentChanged: {
        if (explicitHorizontalAlignment) {
            placeholderTextLabel.horizontalAlignment = horizontalAlignment
        }
    }
    onExplicitHorizontalAlignmentChanged: {
        if (explicitHorizontalAlignment) {
            placeholderTextLabel.horizontalAlignment = horizontalAlignment
        } else {
            placeholderTextLabel.horizontalAlignment = undefined
        }
    }

    function _updateBackground(): void { // Modified by Shipwright for Qt 6: typed
        if (_backgroundItem) {
            _backgroundItem.destroy()
            _backgroundItem = null
        }
        if (!readOnly && background && background.status) {
            _backgroundItem = background.createObject(textBase)
            _backgroundItem.z = -1
        }
    }

    VerticalAutoScroll.keepVisible: activeFocus && autoScrollEnabled

    // If the TextArea/Field has an implicit height we may need to scroll an external flickable to
    // keep the cursor in view.
    VerticalAutoScroll.cursorRectangle: {
        if (!autoScrollEnabled || !activeFocus) {
            return undefined
        }
        var cursor = _editor.cursorRectangle
        var left = Math.max(0, contentContainer.x + _editor.x + cursor.x - (Theme.paddingLarge / 2))
        var right = Math.min(width, left + cursor.width + Theme.paddingLarge)
        var top = Math.max(0, contentContainer.y + _editor.y + cursor.y - (Theme.paddingLarge / 2))
        var bottom = Math.min(height, top + cursor.height + Theme.paddingLarge)

        return Qt.rect(left, top , right - left, bottom - top)
    }

    function _updateLabelItem(): void { // Modified by Shipwright for Qt 6: typed
        if (_labelItem) {
            _labelItem.destroy()
            _labelItem = null
        }

        _labelItem = labelComponent.createObject(labelItemContainer)
    }

    signal clicked(variant mouse)
    signal pressAndHold(variant mouse)

    highlighted: _editor.activeFocus

    opacity: enabled ? 1.0 : Theme.opacityLow

    property int _totalTopMargins: textTopMargin + textTopPadding
    property int _totalLeftMargins: textLeftMargin + textLeftPadding
    property int _totalRightMargins: textRightMargin + textRightPadding
    property int _rightItemWidth: rightItemContainer.active ? rightItemContainer.width : 0
    property int _totalVerticalMargins: Theme.paddingMedium + _totalTopMargins
                                        + (labelVisible ? labelItemContainer.height : 0)
                                        + (descriptionLabel.text.length > 0 ? descriptionLabel.height : Theme.paddingSmall)

    implicitHeight: _editor.height + _totalVerticalMargins
    implicitWidth: parent ? parent.width : KeelSilica.Screen.width

    _keyboardPalette: {
        if (palette.colorScheme !== Theme.colorScheme
                    || palette.highlightColor !== Theme.highlightColor) {
            return JSON.stringify({
                "colorScheme": palette.colorScheme,
                "highlightColor": palette.highlightColor.toString()
            })
        } else {
            return ""
        }
    }

    onBackgroundChanged: _updateBackground()
    onLabelComponentChanged: _updateLabelItem()
    Component.onCompleted: {
        if (!_backgroundItem) {
            _updateBackground()
        }
        if (!_labelItem) {
            _updateLabelItem()
        }

        // Avoid hard dependency to feedback - NOTE: Qt5Feedback doesn't support TextSelection effect
        // Modified by Shipwright for Qt 6: the optional module may be missing; fail quietly
        try {
            // Modified by Shipwright for Qt 6: made by Util._keelOptionalObject (C++), which compiles it once per engine
            _feedbackEffect = KeelPrivate.Util._keelOptionalObject("feedback-pressweak", "import QtFeedback 5.0",
                                                   "ThemeEffect { effect: ThemeEffect.PressWeak }", textBase)
        } catch (e) {
            _feedbackEffect = null
        }

        // calling ThemeEffect.supported initializes the feedback backend,
        // without the initialization here the first playback drops few frames
        if (_feedbackEffect && !_feedbackEffect.supported) {
            _feedbackEffect = null
        }
    }

    // This is the container item for the editor.  It is not the flickable because we want mouse
    // interaction to extend to the full bounds of the item but painting to be clipped so that
    // it doesn't exceed the margins or overlap with the label text.
    Item {
        id: contentContainer

        property alias contentX: flickable.contentX
        property alias contentY: flickable.contentY

        clip: flickable.interactive

        anchors {
            fill: parent
            leftMargin: textBase.textLeftMargin // Modified by Shipwright for Qt 6: qualified
            topMargin: textBase.textTopMargin // Modified by Shipwright for Qt 6: qualified
            rightMargin: textBase.textRightMargin + textBase._rightItemWidth // Modified by Shipwright for Qt 6: qualified
            bottomMargin: textBase._bottomMargin
        }
    }

    Label {
        id: placeholderTextLabel

        text: textBase.label
        color: textBase.highlighted ? palette.secondaryHighlightColor : palette.secondaryColor

        opacity: textBase._isEmpty ? 1.0 : 0.0
        Behavior on opacity {
            id: placeholderBehavior
            FadeAnimation {}
        }
        truncationMode: TruncationMode.Fade
        anchors {
            left: parent.left; top: parent.top; right: parent.right
            leftMargin: textBase._totalLeftMargins // Modified by Shipwright for Qt 6: qualified
            topMargin: textBase._totalTopMargins // Modified by Shipwright for Qt 6: qualified
            rightMargin: textBase._totalRightMargins + textBase._rightItemWidth // Modified by Shipwright for Qt 6: qualified
        }
    }

    OpacityRampEffect {
        id: rampEffect

        offset: 1 - 1 / slope
        states: [
            State {
                name: "verticalOpacityRamp"
                when: flickable.verticalFlick
                PropertyChanges {
                    target: rampEffect
                    sourceItem: contentItem
                    transformOrigin: Item.Center
                    slope: 1 + 10 * textBase.width / KeelSilica.Screen.width
                    direction: {
                        if (flickable.contentY === flickable.originY) {
                            return OpacityRamp.TopToBottom
                        } else if (flickable.contentHeight - flickable.height <= flickable.contentY) {
                            return OpacityRamp.BottomToTop
                        } else {
                            return OpacityRamp.BothEnds
                        }
                    }
                }
            },
            State {
                name: "horizontalOpacityRamp"
                when: flickable.horizontalFlick
                PropertyChanges {
                    target: rampEffect
                    sourceItem: contentItem
                    slope: 1 + 20 * textBase.width / KeelSilica.Screen.width
                    direction: {
                        if (flickable.contentX === flickable.originX) {
                            return OpacityRamp.LeftToRight
                        } else if (flickable.contentWidth - flickable.width <= flickable.contentX) {
                            return OpacityRamp.RightToLeft
                        } else {
                            return OpacityRamp.BothSides
                        }
                    }
                }
            }
        ]
    }

    Flickable {
        id: flickable

        readonly property bool verticalFlick: textBase._editor.height > (contentContainer.height - textBase.textTopPadding) // Modified by Shipwright for Qt 6: qualified
        readonly property bool horizontalFlick: textBase._editor.width > (contentContainer.width - textBase.textLeftPadding - textBase.textRightPadding) // Modified by Shipwright for Qt 6: qualified

        anchors {
            fill: parent
            leftMargin: textBase.textLeftMargin // Modified by Shipwright for Qt 6: qualified
            topMargin: textBase.textTopMargin // Modified by Shipwright for Qt 6: qualified
            rightMargin: textBase.textRightMargin + textBase._rightItemWidth // Modified by Shipwright for Qt 6: qualified
        }

        pixelAligned: true
        contentHeight: scrollProxy.height + textBase._bottomMargin
        contentWidth: scrollProxy.width + Theme.paddingSmall
        interactive: verticalFlick || horizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: scrollProxy

            width: textBase._editor.width + textBase.textLeftPadding + textBase.textRightPadding // Modified by Shipwright for Qt 6: qualified
            height: textBase._editor.height + textBase.textTopPadding // Modified by Shipwright for Qt 6: qualified

            HorizontalAutoScroll.animated: false
            HorizontalAutoScroll.cursorRectangle: textBase._editor.activeFocus && textBase.autoScrollEnabled // Modified by Shipwright for Qt 6: qualified
                                                  ? textBase._editor.cursorRectangle
                                                  : undefined
            HorizontalAutoScroll.leftMargin: Math.max(0, Math.min(
                        Theme.paddingLarge + Theme.paddingSmall,
                        textBase._editor.cursorRectangle.x))
            HorizontalAutoScroll.rightMargin: Math.max(0, Math.min(
                        Theme.paddingLarge + Theme.paddingSmall,
                        width - textBase._editor.cursorRectangle.x - textBase._editor.cursorRectangle.width))
                    + Theme.paddingSmall
            VerticalAutoScroll.animated: false
            VerticalAutoScroll.cursorRectangle: textBase._editor.activeFocus && textBase.autoScrollEnabled // Modified by Shipwright for Qt 6: qualified
                                                ? textBase._editor.cursorRectangle
                                                : undefined
            VerticalAutoScroll.topMargin: Math.max(0, Math.min(
                        Theme.paddingLarge / 2,
                        textBase._editor.cursorRectangle.y))
            VerticalAutoScroll.bottomMargin: Math.max(0, Math.min(
                        Theme.paddingLarge / 2,
                        height - textBase._editor.cursorRectangle.y - textBase._editor.cursorRectangle.height))
                    + textBase._bottomMargin // The interactive area of the flickable extends to the bottom of the root item. This part of the margin ensures the cursor never ventures into that space.
        }
    }

    MouseArea {
        id: mouseArea

        property real initialMouseX
        property real initialMouseY
        property bool hasSelection: textBase._editor !== null && textBase._editor.selectedText != "" // Modified by Shipwright for Qt 6: qualified
        property bool cursorHit
        property bool cursorGrabbed
        property bool handleGrabbed
        property bool textSelected
        property Item selectionStartHandle
        property Item selectionEndHandle
        property int cursorStepThreshold: Theme.itemSizeSmall / 2
        property real scaleFactor: 2
        property int scaleOffset: Theme.itemSizeSmall / 2
        property int scaleTopMargin: Theme.paddingLarge
        property int touchAreaSize: Theme.itemSizeExtraSmall
        property int moveThreshold: Theme.paddingMedium
        property int touchOffset

        function positionAt(mouseX: var, mouseY: var): var { // Modified by Shipwright for Qt 6: typed
            var clippedX = Math.min(Math.max(parent.anchors.leftMargin, mouseX), parent.width + parent.anchors.leftMargin)
            var clippedY = Math.min(Math.max(parent.anchors.topMargin, mouseY), parent.height + parent.anchors.topMargin)
            var translatedPos = mapToItem(textBase._editor, clippedX, clippedY) // Modified by Shipwright for Qt 6: qualified
            translatedPos.x = Math.max(0, Math.min(textBase._editor.width - 1, translatedPos.x)) // Modified by Shipwright for Qt 6: qualified
            translatedPos.y = Math.max(0, Math.min(textBase._editor.height - 1 , translatedPos.y)) // Modified by Shipwright for Qt 6: qualified
            return textBase._editor.positionAt(translatedPos.x, translatedPos.y) // Modified by Shipwright for Qt 6: qualified
        }

        function positionHit(position: var, mouseX: var, mouseY: var): var { // Modified by Shipwright for Qt 6: typed
            var rect = textBase._editor.positionToRectangle(position) // Modified by Shipwright for Qt 6: qualified
            var translatedPos = mapToItem(textBase._editor, mouseX, mouseY) // Modified by Shipwright for Qt 6: qualified
            return translatedPos.x > rect.x - touchAreaSize / 2
                    && translatedPos.x < rect.x + touchAreaSize / 2
                    && translatedPos.y > rect.y
                    && translatedPos.y < rect.y + Math.max(rect.height, touchAreaSize)
        }

        function moved(mouseX: var, mouseY: var): var { // Modified by Shipwright for Qt 6: typed
            return (Math.abs(initialMouseX - mouseX) > moveThreshold
                    || Math.abs(initialMouseY - mouseY) > moveThreshold)
        }

        function updateTouchOffsetAndScaleOrigin(reset: var): void { // Modified by Shipwright for Qt 6: typed
            if (textBase._appWindow !== undefined) { // Modified by Shipwright for Qt 6: qualified
                var cursorRect = textBase._editor.cursorRectangle // Modified by Shipwright for Qt 6: qualified
                var translatedPos = mapToItem(textBase._appWindow._rotatingItem, mouseX, mouseY) // Modified by Shipwright for Qt 6: qualified
                var offset = Math.min(cursorRect.height / 2 + scaleOffset / scaleFactor,
                                      (translatedPos.y - scaleTopMargin) / scaleFactor - cursorRect.height / 2)
                if (reset || offset > touchOffset) {
                    touchOffset = offset
                }

                var cursorPos = textBase._editor.mapToItem(textBase._appWindow._rotatingItem, cursorRect.x, cursorRect.y) // Modified by Shipwright for Qt 6: qualified

                var originX = mouseArea.mapToItem(textBase._appWindow._rotatingItem, mouseX, 0).x // Modified by Shipwright for Qt 6: qualified
                var originY = 0
                if (reset) {
                    originY = (cursorPos.y < (scaleFactor - 1) * cursorRect.height + scaleOffset + scaleTopMargin)
                            ? (scaleFactor * cursorPos.y - scaleTopMargin) / (scaleFactor - 1)
                            : cursorPos.y + cursorRect.height + scaleOffset / (scaleFactor - 1)
                } else {
                    var mappedOrigin = textBase._appWindow.contentItem.mapToItem(textBase._appWindow._rotatingItem, // Modified by Shipwright for Qt 6: qualified
                                                                        textBase._appWindow._contentScale.origin.x, // Modified by Shipwright for Qt 6: qualified
                                                                        textBase._appWindow._contentScale.origin.y) // Modified by Shipwright for Qt 6: qualified
                    var scaledCursorHeight = cursorRect.height * scaleFactor / (scaleFactor - 1)
                    if (cursorPos.y < scaleTopMargin) {
                        originY = Math.max(0, mappedOrigin.y - scaledCursorHeight)
                    } else if (cursorPos.y + scaleFactor * cursorRect.height + Theme.paddingMedium
                               > textBase._appWindow._rotatingItem.height) { // Modified by Shipwright for Qt 6: qualified
                        originY = Math.min(textBase._appWindow._rotatingItem.height, mappedOrigin.y + scaledCursorHeight) // Modified by Shipwright for Qt 6: qualified
                    } else {
                        originY = mappedOrigin.y
                    }
                }

                var mappedPos = textBase._appWindow._rotatingItem.mapToItem(textBase._appWindow.contentItem, originX, originY) // Modified by Shipwright for Qt 6: qualified
                textBase._appWindow._contentScale.origin.x = mappedPos.x // Modified by Shipwright for Qt 6: qualified
                textBase._appWindow._contentScale.origin.y = mappedPos.y // Modified by Shipwright for Qt 6: qualified
            }
        }

        function reset(): void { // Modified by Shipwright for Qt 6: typed
            selectionTimer.stop()
            cursorHit = false
            cursorGrabbed = false
            handleGrabbed = false
            preventStealing = false
            textSelected = false
        }

        parent: flickable
        width: textBase.width
        height: textBase.height
        x: -parent.anchors.leftMargin
        y: -parent.anchors.topMargin
        enabled: textBase.enabled

        onPressed: {
            if (!textBase._editor.activeFocus) { // Modified by Shipwright for Qt 6: qualified
                return
            }
            initialMouseX = mouseX
            initialMouseY = mouseY
            if (!hasSelection) {
                if (positionHit(textBase._editor.cursorPosition, mouseX, mouseY)) { // Modified by Shipwright for Qt 6: qualified
                    cursorHit = true
                }
            } else if (positionHit(textBase._editor.selectionStart, mouseX, mouseY)) { // Modified by Shipwright for Qt 6: qualified
                var selectionStart = textBase._editor.selectionStart // Modified by Shipwright for Qt 6: qualified
                textBase._editor.cursorPosition = textBase._editor.selectionEnd // Modified by Shipwright for Qt 6: qualified
                textBase._editor.moveCursorSelection(selectionStart, TextInput.SelectCharacters) // Modified by Shipwright for Qt 6: qualified
                handleGrabbed = true
                preventStealing = true
            } else if (positionHit(textBase._editor.selectionEnd, mouseX, mouseY)) { // Modified by Shipwright for Qt 6: qualified
                var selectionEnd = textBase._editor.selectionEnd // Modified by Shipwright for Qt 6: qualified
                textBase._editor.cursorPosition = textBase._editor.selectionStart // Modified by Shipwright for Qt 6: qualified
                textBase._editor.moveCursorSelection(selectionEnd, TextInput.SelectCharacters) // Modified by Shipwright for Qt 6: qualified
                handleGrabbed = true
                preventStealing = true
            }
            if (!handleGrabbed) {
                selectionTimer.resetAndRestart()
            }
        }

        // Modified by Shipwright for Qt 6: signal parameter declared
        onClicked: function(mouse) {
            textBase.clicked(mouse)
        }
        // Modified by Shipwright for Qt 6: signal parameter declared
        onPressAndHold: function(mouse) {
            if (!textBase._editor.activeFocus || !textBase._suppressPressAndHoldOnText) { // Modified by Shipwright for Qt 6: qualified
                textBase.pressAndHold(mouse)
            }
        }

        onPositionChanged: {
            if (!handleGrabbed && !cursorGrabbed && moved(mouseX, mouseY)) {
                selectionTimer.stop()
                if (cursorHit) {
                    cursorGrabbed = true
                    preventStealing = true
                    Qt.inputMethod.commit()
                }
            }
            if (handleGrabbed || cursorGrabbed) {
                if (textBase._appWindow !== undefined && textBase._appWindow._contentScale.animationRunning) { // Modified by Shipwright for Qt 6: qualified
                    // Don't change the cursor position during animation
                    return
                }
                updateTouchOffsetAndScaleOrigin(false)
                var cursorPosition = mouseArea.positionAt(mouseX, mouseY - mouseArea.touchOffset)
                if (handleGrabbed) {
                    textBase._editor.moveCursorSelection(cursorPosition, textBase.selectionMode) // Modified by Shipwright for Qt 6: qualified
                } else {
                    textBase._editor.cursorPosition = cursorPosition // Modified by Shipwright for Qt 6: qualified
                }
            }
        }

        onReleased: {
            if (!handleGrabbed && !textSelected && !cursorGrabbed && containsMouse
                    && (textBase.focusOnClick || textBase._editor.activeFocus)) { // Modified by Shipwright for Qt 6: qualified
                Qt.inputMethod.commit()
                var translatedPos = mouseArea.mapToItem(textBase._editor, mouseX, mouseY) // Modified by Shipwright for Qt 6: qualified
                var cursorRect = textBase._editor.positionToRectangle(textBase._editor.cursorPosition) // Modified by Shipwright for Qt 6: qualified
                var cursorPosition = textBase._editor.cursorPosition // Modified by Shipwright for Qt 6: qualified

                // TODO: RTL text should mirror these. at RTL/LTR text block borders should
                // avoid jumping cursor visually far away
                if (translatedPos.x < cursorRect.x && translatedPos.x > cursorRect.x - cursorStepThreshold
                        && translatedPos.y > cursorRect.y && translatedPos.y < cursorRect.y + cursorRect.height) {
                    // step one character backward (unless at line start)
                    if (cursorPosition > 0 && (textBase._editor.positionToRectangle(cursorPosition - 1).x < cursorRect.x)) { // Modified by Shipwright for Qt 6: qualified
                        cursorPosition = textBase._editor.cursorPosition - 1 // Modified by Shipwright for Qt 6: qualified
                    }
                } else if (translatedPos.x > cursorRect.x + cursorRect.width
                           && translatedPos.x < cursorRect.x + cursorRect.width + cursorStepThreshold
                           && translatedPos.y > cursorRect.y && translatedPos.y < cursorRect.y + cursorRect.height) {
                    // step one character forward
                    if (textBase._editor.positionToRectangle(cursorPosition + 1).x > cursorRect.x) { // Modified by Shipwright for Qt 6: qualified
                        cursorPosition = textBase._editor.cursorPosition + 1 // Modified by Shipwright for Qt 6: qualified
                    }
                }

                if (cursorPosition === textBase._editor.cursorPosition) { // Modified by Shipwright for Qt 6: qualified
                    cursorPosition = mouseArea.positionAt(mouseX, mouseY)
                    // NOTE: check for line change might fail, but currently don't care for such minor case
                    if (cursorPosition > 1
                            && textBase._editor.positionToRectangle(cursorPosition - 1).y === textBase._editor.positionToRectangle(cursorPosition).y // Modified by Shipwright for Qt 6: qualified
                            && textBase._editor.text.charAt(cursorPosition - 1) == ' ' // Modified by Shipwright for Qt 6: qualified
                            && textBase._editor.text.charAt(cursorPosition - 2) != ' ' // Modified by Shipwright for Qt 6: qualified
                            && cursorPosition !== textBase._editor.text.length) { // Modified by Shipwright for Qt 6: qualified
                        // space hit, move to the end of the previous word
                        cursorPosition--
                    }
                }
                textBase._editor.cursorPosition = cursorPosition // Modified by Shipwright for Qt 6: qualified
                if (textBase._editor.activeFocus) { // Modified by Shipwright for Qt 6: qualified
                    if (textBase.softwareInputPanelEnabled) {
                        Qt.inputMethod.show()
                    }
                } else {
                    textBase._editor.forceActiveFocus() // Modified by Shipwright for Qt 6: qualified
                }
            }
            reset()
        }

        onCanceled: reset()

        onHasSelectionChanged: {
            if (selectionStartHandle === null) {
                selectionStartHandle = handleComponent.createObject(textBase._editor) // Modified by Shipwright for Qt 6: qualified
                selectionStartHandle.start = true
            }
            if (selectionEndHandle === null) {
                selectionEndHandle = handleComponent.createObject(textBase._editor) // Modified by Shipwright for Qt 6: qualified
                selectionEndHandle.start = false
            }
        }

        onHandleGrabbedChanged: {
            if (!handleGrabbed && textBase._editor.selectedText !== "") { // Modified by Shipwright for Qt 6: qualified
                textBase._editor.copy() // Modified by Shipwright for Qt 6: qualified
            }
        }
    }

    InverseMouseArea {
        anchors.fill: parent
        enabled: textBase._editor.activeFocus && textBase.softwareInputPanelEnabled // Modified by Shipwright for Qt 6: qualified
        onClickedOutside: focusLossTimer.start()
    }

    Item {
        id: labelItemContainer

        anchors {
            left: parent.left; bottom: descriptionLabel.top; right: parent.right
            leftMargin: textBase._totalLeftMargins // Modified by Shipwright for Qt 6: qualified
            rightMargin: textBase._totalRightMargins // Modified by Shipwright for Qt 6: qualified
            bottomMargin: {
                if (descriptionLabel.text.length > 0) {
                    return 0
                } else {
                    return readOnly ? Theme.paddingMedium : Theme.paddingSmall
                }
            }
        }
        visible: textBase.labelVisible // Modified by Shipwright for Qt 6: qualified
        height: children.length > 0 ? children[0].height : 0
    }

    onDescriptionChanged: if (description.length > 0) descriptionLabel.text = description

    Label {
        id: descriptionLabel

        text: textBase.description // Modified by Shipwright for Qt 6: qualified
        wrapMode: Text.Wrap

        color: textBase.errorHighlight ? palette.errorColor
                                       : placeholderTextLabel.color

        font.pixelSize: Theme.fontSizeExtraSmall

        opacity: textBase.description.length > 0 ? 1.0 : 0.0 // Modified by Shipwright for Qt 6: qualified
        Behavior on opacity { FadeAnimator {}}
        height: textBase.description.length > 0 ? implicitHeight : 0 // Modified by Shipwright for Qt 6: qualified
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        bottomPadding: readOnly ? Theme.paddingMedium : Theme.paddingSmall
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: textBase._totalLeftMargins // Modified by Shipwright for Qt 6: qualified
            rightMargin: textBase.textRightMargin // Modified by Shipwright for Qt 6: qualified
            bottomMargin: textBase.description.length > 0 && (textBase._isEmpty && textBase.hideLabelOnEmptyField) // Modified by Shipwright for Qt 6: qualified
                          ? labelItemContainer.height
                          : 0
        }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    }

    Timer {
        id: selectionTimer

        property int counter

        repeat: true

        function resetAndRestart(): void { // Modified by Shipwright for Qt 6: typed
            counter = 0
            interval = 800
            restart()
        }

        function positionAfter(position: var, mouseX: var, mouseY: var): var { // Modified by Shipwright for Qt 6: typed
            var rect = textBase._editor.positionToRectangle(position) // Modified by Shipwright for Qt 6: qualified
            return mouseY > rect.y + Math.max(rect.height, mouseArea.touchAreaSize)
                    || (mouseY >= rect.y
                        && mouseX > rect.x + rect.width + mouseArea.touchAreaSize / 2)
        }

        onTriggered: {
            var origSelectionStart = textBase._editor.selectionStart // Modified by Shipwright for Qt 6: qualified
            var origSelectionEnd = textBase._editor.selectionEnd // Modified by Shipwright for Qt 6: qualified
            var translatedPos = mouseArea.mapToItem(textBase._editor, mouseArea.initialMouseX, mouseArea.initialMouseY) // Modified by Shipwright for Qt 6: qualified
            if (counter == 0) {
                if (textBase._suppressPressAndHoldOnText) { // Modified by Shipwright for Qt 6: qualified
                    Qt.inputMethod.commit()
                    if (textBase._editor.length == 0 || positionAfter(textBase._editor.length - 1, translatedPos.x, translatedPos.y)) { // Modified by Shipwright for Qt 6: qualified
                        // This selection is outside the text itself - deselect and pass through as press-and-hold
                        textBase._editor.deselect() // Modified by Shipwright for Qt 6: qualified
                        mouseArea.reset()
                        textBase.pressAndHold({ 'x': mouseArea.initialMouseX, 'y': mouseArea.initialMouseY })
                        return
                    }
                }

                textBase._editor.cursorPosition = mouseArea.positionAt(mouseArea.initialMouseX, mouseArea.initialMouseY) // Modified by Shipwright for Qt 6: qualified
                textBase._editor.selectWord() // Modified by Shipwright for Qt 6: qualified
                if (origSelectionStart != textBase._editor.selectionStart || origSelectionEnd != textBase._editor.selectionEnd) { // Modified by Shipwright for Qt 6: qualified
                    if (mouseArea.selectionStartHandle !== null)
                        mouseArea.selectionStartHandle.showAnimation.restart()
                    if (mouseArea.selectionEndHandle !== null)
                        mouseArea.selectionEndHandle.showAnimation.restart()
                }
                interval = 600
                // single line editor to skip choosing visible area
                if (textBase._singleLine) {
                    counter++
                }
            } else if (counter == 1) {
                textBase._editor.select(mouseArea.positionAt(0, translatedPos.y), // Modified by Shipwright for Qt 6: qualified
                               mouseArea.positionAt(textBase._editor.width, translatedPos.y)) // Modified by Shipwright for Qt 6: qualified
            } else {
                textBase._editor.cursorPosition = textBase._editor.text.length // Modified by Shipwright for Qt 6: qualified
                textBase._editor.selectAll() // Modified by Shipwright for Qt 6: qualified
                stop()
            }
            if (origSelectionStart != textBase._editor.selectionStart || origSelectionEnd != textBase._editor.selectionEnd) { // Modified by Shipwright for Qt 6: qualified
                if (textBase._feedbackEffect) { // Modified by Shipwright for Qt 6: qualified
                    textBase._feedbackEffect.play() // Modified by Shipwright for Qt 6: qualified
                }
                if (textBase._editor.selectedText !== "") { // Modified by Shipwright for Qt 6: qualified
                    textBase._editor.copy() // Modified by Shipwright for Qt 6: qualified
                }
                mouseArea.textSelected = true
            }
            mouseArea.cursorHit = false
            counter++
        }
    }

    Timer {
        id: focusLossTimer

        interval: 1
        onTriggered: {
            // Note: textBase.focus.  Removing focus from the editor item breaks the focus
            // inheritence chain making it impossible for the editor to regain focus without
            // using forceActiveFocus()
            if (!textBase.activeFocus) {
            } else if (textBase.focusOutBehavior === FocusBehavior.ClearItemFocus) {
                textBase.focus = false
            } else if (textBase.focusOutBehavior === FocusBehavior.ClearPageFocus) {
                // Just remove the focus from the application window (that is a focus scope).
                // This allows an item to clear its active focus without breaking the focus
                // chain within a page.
                if (textBase._appWindow !== undefined) { // Modified by Shipwright for Qt 6: qualified
                    textBase._appWindow.focus = false // Modified by Shipwright for Qt 6: qualified
                } else {
                    textBase.focus = false // fallback
                }
            } else if (!textBase._editor.activeFocus) { // Modified by Shipwright for Qt 6: qualified
                // Happens e.g. when keyboard is closed
                textBase.focus = false
            } else {
                textBase._editor.deselect() // Modified by Shipwright for Qt 6: qualified
            }
            textBase._editor.focus = true // Modified by Shipwright for Qt 6: qualified
        }
    }

    Icon {
        id: errorIcon

        parent: null
        color: Theme.errorColor
        highlightColor: Theme.errorColor
        source: textBase.errorHighlight ? "image://theme/icon-splus-error" : ""
    }

    FontMetrics {
        id: fontMetrics

        font: textBase._editor.font // Modified by Shipwright for Qt 6: qualified
    }

    TextBaseExtensionContainer {
        id: leftItemContainer

        x: textBase.textLeftMargin - (leftItemContainer.active ? leftItemContainer.width + Theme.paddingMedium : 0)
        y: (fontMetrics.height + textBase._totalVerticalMargins - height)/2 // Modified by Shipwright for Qt 6: qualified
        parent: textBase
    }

    TextBaseExtensionContainer {
        id: rightItemContainer

        y: ((textBase._editor.y - textBase.textTopPadding) + fontMetrics.height)/2 - height/2 + textBase._totalTopMargins // Modified by Shipwright for Qt 6: qualified
        parent: textBase
        anchors {
            right: parent.right
            rightMargin: textBase.textRightMargin
        }

        item: textBase.errorHighlight ? errorIcon : null // Modified by Shipwright for Qt 6: qualified
    }

    StateGroup {
        states: State {
            when: (mouseArea.handleGrabbed || mouseArea.cursorGrabbed) && textBase._appWindow !== undefined // Modified by Shipwright for Qt 6: qualified
            PropertyChanges {
                target: _appWindow ? _appWindow._contentScale : null
                xScale: mouseArea.scaleFactor
                yScale: mouseArea.scaleFactor
            }
            StateChangeScript {
                script: {
                    mouseArea.updateTouchOffsetAndScaleOrigin(true)
                }
            }
        }
    }

    Connections {
        ignoreUnknownSignals: true
        target: textBase._editor // Modified by Shipwright for Qt 6: qualified
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onActiveFocusChanged(): void { // Modified by Shipwright for Qt 6: typed
            if (textBase._editor.activeFocus) { // Modified by Shipwright for Qt 6: qualified
                // Modified by Shipwright for Qt 6: a refocus cancels a pending focus loss
                focusLossTimer.stop()
                if (textBase.softwareInputPanelEnabled) {
                    Qt.inputMethod.show()
                }
            } else {
                // When keyboard is explicitly closed (by swipe down) only _editor.focus is cleared.
                // Need to use focusLossTimer for clearing the focus of the parent.
                // (See the comments in focusLossTimer.)
                focusLossTimer.start()
            }
        }
    }

    Component {
        id: handleComponent

        Rectangle {
            id: handleId

            property bool start
            property var cursorRect: {
                textBase._editor.width // creates a binding. we want to refresh the cursor rect e.g. on orientation change // Modified by Shipwright for Qt 6: qualified
                textBase._editor.positionToRectangle(start ? textBase._editor.selectionStart : textBase._editor.selectionEnd) // Modified by Shipwright for Qt 6: qualified
            }
            property alias showAnimation: showAnimationId
            property int xAnimationLength: Theme.itemSizeExtraLarge

            color: textBase.cursorColor
            parent: textBase._editor // Modified by Shipwright for Qt 6: qualified
            x: Math.round(cursorRect.x + cursorRect.width / 2 - width / 2)
            y: Math.round(cursorRect.y + cursorRect.height / 2 - height / 2)
            width: Math.round(Theme.iconSizeSmall / 4) * 2 // ensure even number
            height: width
            radius: width / 2
            smooth: true
            visible: mouseArea.hasSelection && textBase.activeFocus

            states: State {
                when: mouseArea.handleGrabbed
                name: "grabbed"
                PropertyChanges {
                    target: handleId
                    width: 2
                    height: cursorRect.height
                    radius: 0
                }
            }

            transitions: Transition {
                to: "grabbed"
                reversible: true
                SequentialAnimation {
                    NumberAnimation { property: "width"; duration: 100 }
                    PropertyAction { property: "radius" }
                    NumberAnimation { property: "height"; duration: 100 }
                }
            }

            ParallelAnimation {
                id: showAnimationId

                FadeAnimation {
                    target: handleId
                    from: 0
                    to: 1
                }
                NumberAnimation {
                    target: handleId
                    property: "x"
                    from: start ? handleId.x - handleId.xAnimationLength : handleId.x + handleId.xAnimationLength // Modified by Shipwright for Qt 6: qualified
                    to: handleId.x
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }
}
