// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick
import Qt.labs.folderlistmodel
import MarathonApp.Camera

// The camera roll for the Jolla Camera's gallery: the capture folder, newest
// first. The folder is watched, so a new capture appears on its own.
FolderListModel {
    readonly property bool populated: status === FolderListModel.Ready

    function appendCapture(url, mimeType) {
    }

    function deleteFile(index) {
        Settings.captures.remove(get(index, "filePath"));
    }

    folder: Settings.captureFolder
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.mp4"]
    showDirs: false
    sortField: FolderListModel.Time
}
