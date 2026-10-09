// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 FolderPickerPage, Keel's clean-room version: picks a
// directory, browsing from the home directory (from the file system root
// with showSystemFiles). Public API (dialogTitle, selectedPath,
// showSystemFiles, title) and defaults from the Sailfish.Pickers
// documentation; selecting sets selectedPath and returns to the page below.
import QtQuick 2.6
import Sailfish.Pickers 1.0

FolderBrowserPage {
    id: page

    property string selectedPath

    function _selectPath(path) {
        selectedPath = path
        if (!pageStack)
            return
        var below = null
        try {
            below = pageStack.previousPage(page)
        } catch (e) {
            return
        }
        if (below)
            pageStack.pop(below)
        else
            pageStack.pop()
    }

    title: qsTr("Select location")
    path: showSystemFiles ? "/" : ""
}
