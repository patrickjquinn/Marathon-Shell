// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the multi pickers' selection, kept by file path across
// folder changes, mirrored into the ListModel the dialogs expose as
// selectedContent (roles fileName, filePath, url, title, mimeType, as the
// Sailfish.Pickers documentation lists them).
import QtQuick 2.6

QtObject {
    id: selection

    property ListModel model: ListModel { }
    property var _paths: ({})
    property int revision
    readonly property int count: revision >= 0 ? model.count : 0

    function contains(path) {
        return revision >= 0 && _paths[path] === true
    }

    function toggle(props) {
        var path = props.filePath
        if (_paths[path] === true) {
            delete _paths[path]
            for (var i = 0; i < model.count; ++i) {
                if (model.get(i).filePath === path) {
                    model.remove(i)
                    break
                }
            }
        } else {
            _paths[path] = true
            model.append({
                "fileName": props.fileName,
                "filePath": props.filePath,
                "url": String(props.url),
                "title": props.title,
                "mimeType": props.mimeType
            })
        }
        revision++
    }

    function clear() {
        _paths = {}
        model.clear()
        revision++
    }
}
