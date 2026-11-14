// SPDX-FileCopyrightText: 2016 Jolla Ltd
// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2016 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jolla.com>
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebEngine 1.0
import Sailfish.Pickers 1.0

ContextMenuItem {
    id: root

    property string targetDirectory
    property string linkUrl
    property string contentType
    property int viewId

    function startDownload() {
        // Hack: Evaluate binding whenever menu is shown.
        var updater = root.parent.visible

        // drop query string from URL and split to sections
        var urlSections = linkUrl.split("?")[0].split("/")
        var leafName = decodeURIComponent(urlSections[urlSections.length - 1])

        if (leafName.length === 0) {
            leafName = "unnamed_file"
        }
        var downloadFileTargetUrl = DownloadHelper.createUniqueFileUrl(leafName, targetDirectory)

        if (downloadFileTargetUrl) {
            WebEngine.notifyObservers("embedui:download",
                                      {
                                          "msg": "addDownload",
                                          "from": root.linkUrl,
                                          "to": downloadFileTargetUrl,
                                          "contentType": root.contentType,
                                          "viewId": root.viewId
                                      })
        }
    }

    onClicked: {
        if (WebEngineSettings.useDownloadDir) {
            root.targetDirectory = WebEngineSettings.downloadDir
            startDownload()
        } else {
            pageStack.animatorPush(folderPickerPage)
        }
    }

    Component {
        id: folderPickerPage

        FolderPickerPage {
            showSystemFiles: false
            //% "Download to"
            dialogTitle: qsTrId("sailfish_components_webview_popups-ti-download-to")

            onSelectedPathChanged: {
                root.targetDirectory = selectedPath
                startDownload()
            }
        }
    }
}
