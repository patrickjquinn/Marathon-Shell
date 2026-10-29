import QtQuick

// FileChooserModel over a fixed tree.
ListModel {
    id: root

    property string folder: ""
    property var nameFilters: []
    property var mimeFilters: []
    property bool showHidden: false
    property bool directoriesOnly: false
    property string search: ""
    property bool recent: false
    readonly property var tree: ({
            "/home/u": [
                {
                    "name": "Documents",
                    "isDir": true
                },
                {
                    "name": "Pictures",
                    "isDir": true
                },
                {
                    "name": "todo.txt"
                }
            ],
            "/home/u/Documents": [
                {
                    "name": "Old",
                    "isDir": true
                },
                {
                    "name": "report.pdf"
                }
            ],
            "/home/u/Documents/Old": [],
            "/home/u/Pictures": [
                {
                    "name": "beach.png",
                    "isImage": true
                },
                {
                    "name": "sea.png",
                    "isImage": true
                },
                {
                    "name": "notes.txt"
                }
            ]
        })

    function places() {
        return [
            {
                "name": "Home",
                "path": "/home/u"
            },
            {
                "name": "Documents",
                "path": "/home/u/Documents"
            },
            {
                "name": "Pictures",
                "path": "/home/u/Pictures"
            }
        ];
    }

    function exists(path) {
        if (tree[path] !== undefined)
            return true;
        const at = path.lastIndexOf("/");
        return (tree[path.substring(0, at)] || []).some(e => e.name === path.substring(at + 1));
    }

    function join(folder, name) {
        return folder + "/" + name;
    }

    function reload() {
        clear();
        for (const e of tree[folder] || []) {
            if (directoriesOnly && !e.isDir)
                continue;
            if (!e.isDir && mimeFilters.length > 0 && !e.isImage)
                continue;
            append({
                "name": e.name,
                "path": folder + "/" + e.name,
                "isDir": !!e.isDir,
                "isImage": !!e.isImage,
                "size": 1024,
                "url": ""
            });
        }
    }

    onFolderChanged: reload()
    onDirectoriesOnlyChanged: reload()
    onMimeFiltersChanged: reload()
}
