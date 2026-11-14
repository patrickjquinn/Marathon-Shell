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
import Sailfish.Silica.private 1.0 as Private
import "private"
import "private/Util.js" as Util

Private.SilicaMouseArea {
    id: miniComboBox

    //% "Select"
    //: Default text of inline combo box when it's empty, also used as a dialog header when it has too many options.
    property string label: qsTrId("components-la-select")

    property alias menu: controller.menu
    property alias currentIndex: controller.currentIndex
    property alias currentItem: controller.currentItem
    property alias value: controller.value
    readonly property real contentHeight: contentRow.height

    property Item _textField: Util.findParentWithProperty(miniComboBox, "__silica_textfield")
    property bool __silica_miniComboBox: true
    readonly property bool _showPress: (pressed && containsMouse) || pressTimer.running
    readonly property bool _menuOpen: controller.menuOpen

    // TextField can be highlighted without being focused, so ensure both are true before expanding.
    readonly property bool _expanded: (_textField === null) || (_textField.activeFocus && _textField.highlighted)
    readonly property bool _parentIsRow: parent && Private.Util.instanceOf(parent, "QQuickRow")

    highlighted: _showPress

    height: _menuOpen ? (menu.height + contentRow.height + Theme.paddingSmall) : contentRow.height
    implicitWidth: buttonText.implicitWidth + (3 * Theme.paddingSmall) + Theme.iconSizeSmall
    width: {
        if (!parent) return 0

        var leftPadding = parent.leftPadding || parent.padding || 0
        var rightPadding = parent.rightPadding || parent.padding || 0
        var availableWidth = parent.width - leftPadding - rightPadding

        if (!_parentIsRow) {
            return Math.min(implicitWidth, availableWidth)
        }

        // Find the child count and total implicit width, filter out stuff added by the context menu
        // Assumptions: the parent width is set correctly, parent row only contains miniComboBox instances,
        // and they use this code for their width
        var count = 0
        var totalImplicitWidth = 0
        for (var i = 0; i < parent.children.length; i++) {
            if (parent.children[i].__silica_miniComboBox) {
                count++
                totalImplicitWidth += parent.children[i].implicitWidth
            }
        }

        var spacing = parent.spacing || 0.0
        var totalSpacing = spacing * (count - 1)
        availableWidth -= totalSpacing

        if (totalImplicitWidth <= availableWidth) {
            return implicitWidth
        }

        var averageWidthPerChild = (parent.width - totalSpacing) / count

        if (implicitWidth <= averageWidthPerChild) {
            return implicitWidth
        }

        var resizableChildCount = 0
        for (i = 0; i < parent.children.length; i++) {
            if (parent.children[i].__silica_miniComboBox) {
                if (parent.children[i].implicitWidth <= averageWidthPerChild) {
                    availableWidth -= parent.children[i].implicitWidth
                } else {
                    resizableChildCount++
                }
            }
        }

        var fitWidth = Math.min(availableWidth / resizableChildCount, implicitWidth)
        return Math.max(fitWidth, 0)
    }

    onClicked: {
        if (!_textField || _textField.focus) {
            controller.openMenu()
        } else {
            _textField.forceActiveFocus()
        }
    }

    Connections {
        target: _textField
        onHighlightedChanged: {
            if (controller.menuOpen) {
                controller.menu.close()
            }
        }
    }

    ComboBoxController {
        id: controller

        comboBox: miniComboBox
    }

    Row {
        id: contentRow

        spacing: Theme.paddingSmall
        rightPadding: Theme.paddingSmall

        Label {
            id: buttonText

            anchors.verticalCenter: parent.verticalCenter

            color: miniComboBox._expanded
                   ? (_showPress ? palette.highlightColor : palette.primaryColor)
                   : palette.secondaryHighlightColor

            font.pixelSize: Theme.fontSizeSmall
            text: (currentItem !== null) ? miniComboBox.value : label
            truncationMode: TruncationMode.Fade
            width: miniComboBox.width - (3 * Theme.paddingSmall) - Theme.iconSizeSmall
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            opacity: miniComboBox._expanded ? 1.0 : Theme.opacityLow
            source: miniComboBox._expanded ? "image://theme/icon-s-down" : "image://theme/icon-s-unfocused-down"
            color: miniComboBox._expanded ? palette.primaryColor : palette.secondaryHighlightColor
        }
    }

    Timer {
        id: pressTimer
        interval: Theme.minimumPressHighlightTime
    }
}
