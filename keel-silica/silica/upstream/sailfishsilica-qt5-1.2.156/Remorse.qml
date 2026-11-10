/****************************************************************************************
**
** Copyright (C) 2016 - 2019 Jolla Ltd.
** Copyright (c) 2019 Open Mobile Platform LLC.
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

pragma Singleton
import QtQuick 2.2
import Sailfish.Silica.private 1.0

QtObject {
    property Component _itemComponent
    property Component _popupComponent

    //% "Deleted"
    readonly property string deletedText: qsTrId("components-la-deleted")

    function _create(component, parent) {
        if (!parent.RemorseCache.item) {
            parent.RemorseCache.item = component.createObject(parent)
        }

        return parent.RemorseCache.item
    }

    function itemAction(item, text, callback, timeout) {
        if (!_itemComponent) {  // Including the components inline silently breaks all of Silica.  True story.
            _itemComponent = Qt.createComponent(Qt.resolvedUrl("RemorseItem.qml"))
        }

        var remorseItem = _create(_itemComponent, item)

        if (remorseItem) {
            remorseItem.execute(item, text, callback, timeout)
        } else if (_itemComponent) {
            console.warn("Failed to create RemorseItem", _itemComponent.errorString())
        }

        return remorseItem
    }

    function popupAction(page, text, callback, timeout) {
        if (!_popupComponent) {
            _popupComponent = Qt.createComponent(Qt.resolvedUrl("RemorsePopup.qml"))
        }

        var remorsePopup = _create(_popupComponent, page)

        if (remorsePopup) {
            remorsePopup.execute(text, callback, timeout)
        } else if (_popupComponent) {
            console.warn("Failed to create RemorsePopup", _popupComponent.errorString())
        }

        return remorsePopup
    }
}
