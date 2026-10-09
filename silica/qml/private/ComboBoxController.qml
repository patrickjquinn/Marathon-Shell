// SPDX-FileCopyrightText: 2013-2019 Jolla Ltd
// SPDX-FileCopyrightText: 2019-2020 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (c) 2013 - 2019 Jolla Ltd.
** Copyright (c) 2019 - 2020 Open Mobile Platform LLC.
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/ComboBoxController.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places).
// Modified by Shipwright for Qt 6: imports Sailfish.Silica.private for the module's native types.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6).

import QtQuick 2.6
import Sailfish.Silica 1.0
import "Util.js" as Util
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: native types of this module

Item {
    id: controller

    property Item menu
    property Item comboBox

    // Setting currentItem to a non-enabled or non-MenuItem-child object
    // will clear the selection. Is this what we want or should it track
    // the 'previous' currentItem and index and revert to those?

    property int currentIndex   // setting to invalid index clears the selection
    property Item currentItem   // setting to null or invalid item clears the selection

    property string value: (currentItem !== null && currentItem.text !== "") ? currentItem.text : ""
    readonly property bool menuOpen: menu !== null && menu.parent === comboBox
    property bool automaticSelection: true

    property bool _updating
    property bool _completed
    property bool _currentIndexSet
    property Page _menuDialogItem
    property Page _page

    onCurrentIndexChanged: {
        _currentIndexSet = true
        if (_completed && !_updating) {
            _updating = true
            _updateCurrent(currentIndex, null)
            _updating = false
        }
    }

    onCurrentItemChanged: {
        if (_completed && !_updating) {
            _updating = true
            _updateCurrent(-1, currentItem)
            _updating = false
        }
    }

    Component.onCompleted: {
        if (menu) {
            _loadCurrent()
        }
        _completed = true
    }

    function openMenu() {
        if (!controller.menu) {
            return
        }
        var needSeparateDialog = false
        var menuChildrenCount = 0
        var maximumInlineItems = screen.sizeCategory >= KeelSilica.Screen.Large ? 6 : 5

        if (!_page) {
            _page = Util.findPage(controller.comboBox)
        }

        if (_page && _page.isLandscape && Qt.inputMethod.visible) {
            // In landscape mode when the VKB is visible the menu doesn't fit the page
            needSeparateDialog = true
        } else {
            for (var i = 0; i < menu._contentColumn.children.length; i++) {
                var child = menu._contentColumn.children[i]
                if (child && child.visible && child.hasOwnProperty("__silica_menuitem")) {
                    if (++menuChildrenCount > maximumInlineItems) {
                        needSeparateDialog = true
                        break
                    }
                }
            }
        }

        if (needSeparateDialog) {
            _openSeparateDialog()
        } else {
            controller.menu.open(controller.comboBox)
        }
    }

    function _openSeparateDialog() {
        _menuDialogItem = pageStack.push(menuDialogComponent)
    }

    function _clearCurrent() {
        currentIndex = -1
        currentItem = null
        controller.menu._setHighlightedItem(null)
    }

    function _resetCurrent() {
        _updating = true
        currentIndex = 0
        _currentIndexSet = false
        currentItem = null
        _updating = false
    }

    function _loadCurrent() {
        if (currentIndex == -1 && currentItem == null) {
            _clearCurrent()
        } else {
            if (currentItem != null) {
                _updateCurrent(-1, currentItem)
            } else {
                _updateCurrent(currentIndex, null)
            }
        }
    }

    function _updateCurrent(newIndex, newItem) {
        if (!menu) {
            return
        }
        if (newIndex < 0 && newItem === null) {
            _clearCurrent()
            return
        }

        var menuItemIndex = -1
        var matched = false
        for (var i = 0; i < menu._contentColumn.children.length; i++) {
            var child = menu._contentColumn.children[i]
            if (child && child.hasOwnProperty("__silica_menuitem")) {
                menuItemIndex++
                if (newIndex >= 0 ? newIndex === menuItemIndex : child === newItem) {
                    if (child.enabled) {
                        currentIndex = menuItemIndex
                        currentItem = child
                        if (menu.active) {
                            _highlightCurrent()
                        }
                        matched = true
                    }
                    break
                }
            }
        }
        if (!matched) {
            if (newIndex >= 0 && _currentIndexSet) {
                console.log("ComboBox: specified currentIndex has invalid value", newIndex)
                _clearCurrent()
            } else if (currentItem !== null) {
                console.log("ComboBox: specified currentItem has enabled=false or is not a MenuItem child")
                _clearCurrent()
            }
        }
    }

    function _highlightCurrent() {
        controller.menu._setHighlightedItem(currentItem)
    }

    Connections {
        target: controller.menu
        // Modified by Shipwright for Qt 6: Connections handler as a function (ContextMenu.activated(int index))
        function onActivated(index) {
            if (controller.automaticSelection) {
                controller.currentIndex = index
            }
        }
    }

    Connections {
        target: controller.menu ? controller.menu._contentColumn : null
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onChildrenChanged() {
            // delay the reload in case there are more children changes to come
            if (!updateCurrentTimer.running) {
                _updating = true
                updateCurrentTimer.start()
            }
        }
    }

    Connections {
        target: _page
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onIsLandscapeChanged() {
            // When the menu is already open and the keyboard is shown, but the user
            // switches to landscape mode, the menu will no longer properly fit the screen.
            // So we have to close it and open the separate dialog after it is closed.
            if (_page.isLandscape && controller.menuOpen && Qt.inputMethod.visible) {
                // NOTE: attempting pageStack.animatorPush while the menu is still open will bork the dialog.
                menu.close()
                menu.closed.connect(function menuClosed() {
                    menu.closed.disconnect(menuClosed)
                    _openSeparateDialog()
                })
            }
        }
    }

    Timer {
        id: updateCurrentTimer

        interval: 1
        onTriggered: {
            _updating = false
            // ignore if no current index was set
            if (controller.currentItem === null && controller.currentIndex < 0) {
                return
            }
            if (controller.currentItem) {
                var menuItems = controller.menu._contentColumn.children
                var foundOldCurrentItem = false
                for (var i=0; i<menuItems.length; i++) {
                    if (menuItems[i] === controller.currentItem) {
                        foundOldCurrentItem = true
                        break
                    }
                }
                // ContextMenu has completely changed its items, so reload the combo box
                if (!foundOldCurrentItem) {
                    controller._resetCurrent()
                }
            }
            controller._loadCurrent()
        }
    }

    Component {
        id: menuDialogComponent

        Page {
            allowedOrientations: _page ? _page.allowedOrientations : Orientation.All

            Component.onCompleted: {
                var menuIndex = 0
                var menuItems = controller.menu.children
                for (var i = 0; i < menuItems.length; i++) {
                    var child = menuItems[i]
                    if (child && child.hasOwnProperty("__silica_menuitem")) {
                        if (child.visible) {
                            items.append( {"item": child, "menuIndex": menuIndex } )
                        }
                        menuIndex++
                    }
                }
            }

            ListModel {
                id: items
            }

            SilicaListView {
                anchors.fill: parent
                model: items

                header: PageHeader {
                    title: controller.comboBox.label
                }

                delegate: BackgroundItem {
                    id: delegateItem

                    readonly property bool _isMultiLine: descriptionLabel.text.length || mainLabel.lineCount > 1

                    height: Math.max(labelColumn.height + Theme.paddingMedium*2, Theme.itemSizeSmall)

                    onClicked: {
                        model.item.clicked()
                        controller.menu.activated(model.menuIndex)
                        pageStack.pop()
                    }

                    HighlightImage {
                        id: icon

                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin

                            // If there is only one line of text, vertically center the icon.
                            // Otherwise, anchor it to the delegate's top, with a small padding.
                            top: _isMultiLine ? parent.top : undefined
                            topMargin: Theme.paddingMedium + Theme.paddingSmall
                            verticalCenter: _isMultiLine ? undefined : parent.verticalCenter
                        }
                        sourceSize.width: Theme.iconSizeMedium
                        sourceSize.height: Theme.iconSizeMedium
                        source: model.item.icon ? model.item.icon.source : ""
                        highlighted: mainLabel.highlighted
                        monochromeWeight: !!model.item.icon && model.item.icon.monochromeWeight !== undefined
                                          ? model.item.icon.monochromeWeight
                                          : 1.0
                    }

                    Column {
                        id: labelColumn

                        anchors {
                            left: model.item.icon ? icon.right : parent.left
                            leftMargin: model.item.icon ? Theme.paddingMedium : Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }

                        Label {
                            id: mainLabel

                            width: parent.width
                            wrapMode: Text.Wrap
                            text: model.item.text
                            highlighted: delegateItem.highlighted || model.item === controller.currentItem
                        }

                        Label {
                            id: descriptionLabel

                            width: parent.width
                            height: text.length ? implicitHeight : 0
                            font.pixelSize: Theme.fontSizeExtraSmall
                            wrapMode: Text.Wrap
                            text: model.item.description || ""
                            highlighted: mainLabel.highlighted
                            color: highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                    }
                }

                VerticalScrollDecorator {}
            }
        }
    }

    states: State {
        when: controller.menu && controller.menu.active

        StateChangeScript {
            script: {
                if (!controller.currentItem) {
                    controller._loadCurrent()
                }
                if (controller.currentItem) {
                    controller._highlightCurrent()
                }
            }
        }
    }
}
