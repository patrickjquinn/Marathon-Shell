// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.0
import Sailfish.WebEngine 1.0
import Sailfish.Pickers 1.0

FolderPickerPage {
    id: root

    property var data
    property var closedCallback
    property bool responseSent

    showSystemFiles: false

    //% "Download to"
    dialogTitle: qsTrId("sailfish_browser-ti-download-to")

    onSelectedPathChanged: {
        var response = {
            "downloadDirectory": selectedPath,
            "defaultFileName": data.defaultFileName,
            "suggestedFileExtension": data.suggestedFileExtension
        }
        if (data.winId !== undefined) {
            response.winId = data.winId
        }
        if (data.tabId !== undefined) {
            response.tabId = data.tabId
        }
        if (data.persistentId !== undefined) {
            response.persistentId = data.persistentId
        }
        if (data.requestId !== undefined) {
            response.requestId = data.requestId
        }
        responseSent = true
        WebEngine.notifyObservers("embedui:downloadpicker", response)
    }

    Component.onDestruction: {
        if (!responseSent && data && data.requestId !== undefined) {
            var response = {
                "cancelled": true,
                "requestId": data.requestId
            }
            if (data.winId !== undefined) {
                response.winId = data.winId
            }
            if (data.tabId !== undefined) {
                response.tabId = data.tabId
            }
            if (data.persistentId !== undefined) {
                response.persistentId = data.persistentId
            }
            WebEngine.notifyObservers("embedui:downloadpicker", response)
        }
        if (closedCallback) {
            closedCallback()
        }
    }
}
