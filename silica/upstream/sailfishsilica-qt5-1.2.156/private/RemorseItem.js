/****************************************************************************************
**
** Copyright (c) 2021 Open Mobile Platform LLC.
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

.pragma library

var activeContextMenus = new Array
var activeRemorseItems = new Array
var pendingRemorseItems = new Array

function activeChanged(menu, active)
{
    if (active) {
        if (activeContextMenus.indexOf(menu) == -1) {
            activeContextMenus.push(menu)
        }
    } else {
        var index = activeContextMenus.indexOf(menu)
        if (index != -1) {
            activeContextMenus.splice(index, 1)

            if (activeContextMenus.length == 0) {
                for (var i = 0; i < pendingRemorseItems.length; ++i) {
                    var item = pendingRemorseItems[i]
                    _executeRemorseAction(item.item, item.callback, item.closeAfterExecute)
                }
                pendingRemorseItems.splice(0, pendingRemorseItems.length)
            }
        }
    }
}

function _executeRemorseAction(item, callback, closeAfterExecute)
{
    item.triggered()

    if (callback !== undefined) {
        callback.call()

        var index = activeRemorseItems.indexOf(item)
        if (index == -1) {
            // The callback resulted in the destruction of the item
            return
        }
    }

    if (closeAfterExecute) {
        item._close()
    } else {
        remorseItemDeactivated(item)
    }
}

function remorseItemTrigger(item, callback, closeAfterExecute)
{
    if (activeContextMenus.length == 0) {
        _executeRemorseAction(item, callback, closeAfterExecute)
    } else {
        pendingRemorseItems.push({
            'item': item,
            'callback': callback,
            'closeAfterExecute': closeAfterExecute
        })
    }
}

function remorseItemCancel(item)
{
    delete pendingRemorseItems[item]
}

function remorseItemActivated(item)
{
    activeRemorseItems.push(item)
}

function remorseItemDeactivated(item)
{
    var index = activeRemorseItems.indexOf(item)
    if (index != -1) {
        activeRemorseItems.splice(index, 1)
    }
}
