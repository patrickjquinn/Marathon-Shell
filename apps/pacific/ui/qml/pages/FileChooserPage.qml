// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Choosing a file: for a page's upload field, or a bookmarks file to
// import. Uses Sailfish's file picker.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Pickers 1.0
import Shipwright.Pacific 1.0

FilePickerPage {
    id: picker

    property var request: null
    property bool importBookmarks: false
    property bool _answered: false

    title: importBookmarks ? qsTr("Bookmarks file") : qsTr("Choose a file")
    nameFilters: importBookmarks ? ["*.html", "*.htm"] : []

    onSelectedContentPropertiesChanged: {
        var path = selectedContentProperties.filePath;
        if (!path)
            return;
        _answered = true;
        if (importBookmarks)
            Pacific.importBookmarks(path);
        else if (request)
            request.select([path]);
    }

    Component.onDestruction: {
        if (request && !_answered)
            request.cancel();
    }
}
