// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers pages and dialogs used as the Sailfish.Pickers
// documentation shows them (and as bitsailor and sfos-forum-viewer do): push
// the picker from an app page, tap an item, read selectedContentProperties
// or selectedContent. Runs on the fake home directory written by
// `tst_keel_pickers --make-fixture` (HOME points at it; Tracker is off).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Item {
    width: 540
    height: 960
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { objectName: "app" } }
    }

    property var log: []

    Component {
        id: imagePicker
        ImagePickerPage {
            onSelectedContentPropertiesChanged: log.push(selectedContentProperties.filePath)
        }
    }
    Component {
        id: contentPicker
        ContentPickerPage {
            title: "Select file"
            onSelectedContentPropertiesChanged: log.push(selectedContentProperties.fileName)
        }
    }
    Component {
        id: filePicker
        FilePickerPage {
            nameFilters: [ '*.pdf', '*.doc' ]
            onSelectedContentPropertiesChanged: log.push(selectedContentProperties.filePath)
        }
    }
    Component {
        id: multiImage
        MultiImagePickerDialog {
            title: "Select images"
            onAccepted: {
                var urls = []
                for (var i = 0; i < selectedContent.count; ++i)
                    urls.push(String(selectedContent.get(i).url))
                log.push(urls.join(","))
            }
        }
    }
    Component {
        id: multiFile
        MultiFilePickerDialog {
            nameFilters: [ '*.pdf' ]
            onAccepted: log.push("files:" + selectedContent.count)
        }
    }
    Component {
        id: folderDialog
        FolderPickerDialog {
            title: "Download to"
            onAccepted: log.push(selectedPath)
            onRejected: log.push("")
        }
    }
    Component {
        id: folderPage
        FolderPickerPage {
            dialogTitle: "Save to"
        }
    }
    Component {
        id: multiContent
        MultiContentPickerDialog { }
    }
    Component {
        id: everyType
        Item {
            DocumentPickerPage { }
            DownloadPickerPage { }
            MusicPickerPage { }
            VideoPickerPage { }
            MultiDocumentPickerDialog { }
            MultiDownloadPickerDialog { }
            MultiMusicPickerDialog { }
            MultiVideoPickerDialog { }
        }
    }

    TestCase {
        name: "Pickers"
        when: windowShown

        function init() {
            win.pageStack.completeAnimation()
            tryCompare(win.pageStack, "busy", false)
            while (win.pageStack.depth > 1)
                win.pageStack.pop(undefined, PageStackAction.Immediate)
            log = []
        }

        function push(component, props) {
            tryCompare(win.pageStack, "busy", false)
            var p = win.pageStack.push(component, props || {}, PageStackAction.Immediate)
            tryCompare(win.pageStack, "busy", false)
            return p
        }

        function clickRow(view, index) {
            // Click only once the view has laid out, rendered and settled:
            // a click on a delegate that is still being positioned can land
            // on the page instead (seen once in CI: the picker closed with
            // nothing picked).
            view.forceLayout()
            tryVerify(function() { return !view.moving && !view.flicking })
            waitForRendering(view)
            var item = view.itemAtIndex(index)
            verify(item, "row " + index)
            tryVerify(function() { return item.visible && item.width > 0 && item.height > 0 },
                      5000, "row " + index + " is laid out")
            mouseClick(item)
            return item
        }

        function test_image_picker_tap_selects_and_returns() {
            var p = push(imagePicker)
            compare(p.title, "Select image")
            tryCompare(p._model, "loading", false)
            compare(p._model.count, 2) // beach.png, Camera/older.png; not Music art or hidden
            compare(p._model.source, "filesystem")
            var grid = p._view.flickable
            verify(grid)
            tryVerify(function() { return grid.count === 2 })
            clickRow(grid, 0)
            tryVerify(function() { return log.length === 1 }, 5000,
                      "one pick recorded (log: " + JSON.stringify(log) + ", depth " + win.pageStack.depth + ")")
            tryCompare(win.pageStack, "depth", 1)
            verify(log[0].match(/\/Pictures\/beach\.png$/), log[0])
            compare(p.selectedContentProperties.fileName, "beach.png")
            compare(p.selectedContentProperties.title, "beach")
            compare(p.selectedContentProperties.mimeType, "image/png")
            compare(String(p.selectedContent), String(p.selectedContentProperties.url))
        }

        function test_content_picker_category_then_item() {
            var p = push(contentPicker)
            compare(p._list.count, 4)
            clickRow(p._list, 1) // Images
            tryCompare(win.pageStack, "depth", 3)
            var sub = win.pageStack.currentPage
            tryCompare(sub._model, "loading", false)
            clickRow(sub._view.flickable, 1) // older.png
            tryCompare(win.pageStack, "depth", 1)
            compare(log, ["older.png"])
            compare(p.selectedContentProperties.fileName, "older.png")
        }

        function test_file_picker_browses_folders_with_filters() {
            var p = push(filePicker)
            compare(p.title, "Select location")
            // Home: Documents, Downloads, Music, Pictures, Videos; other.bin is filtered out.
            compare(p._list.count, 5)
            clickRow(p._list, 0) // Documents
            tryCompare(win.pageStack, "depth", 3)
            var docs = win.pageStack.currentPage
            compare(docs._list.count, 2) // Sub/, report.pdf (notes.txt filtered)
            clickRow(docs._list, 1)
            tryCompare(win.pageStack, "depth", 1)
            compare(log.length, 1)
            verify(log[0].match(/\/Documents\/report\.pdf$/), log[0])
            compare(p.selectedContentProperties.mimeType, "application/pdf")
        }

        function test_multi_image_dialog() {
            var d = push(multiImage)
            tryCompare(d._model, "loading", false)
            verify(!d.canAccept)
            var grid = d._view.flickable
            tryVerify(function() { return grid.count === 2 })
            clickRow(grid, 0)
            clickRow(grid, 1)
            compare(d.selectedContent.count, 2)
            clickRow(grid, 1) // toggles off
            compare(d.selectedContent.count, 1)
            verify(d.canAccept)
            compare(d.selectedContent.get(0).fileName, "beach.png")
            d.accept()
            tryCompare(win.pageStack, "depth", 1)
            compare(log.length, 1)
            verify(log[0].match(/^file:\/\/.*\/Pictures\/beach\.png$/), log[0])
        }

        function test_multi_file_dialog_keeps_selection_across_folders() {
            var d = push(multiFile)
            compare(d.title, "Select location")
            var list = d._list
            clickRow(list, 0) // Documents
            tryCompare(d._folderModel, "count", 2)
            clickRow(list, 1) // report.pdf
            compare(d.selectedContent.count, 1)
            d._folderModel.path = d._folderModel.parentPath
            clickRow(list, 1) // Downloads
            tryCompare(d._folderModel, "count", 1) // manual.pdf (archive.zip filtered)
            clickRow(list, 0)
            compare(d.selectedContent.count, 2)
            d.accept()
            tryCompare(win.pageStack, "depth", 1)
            compare(log, ["files:2"])
        }

        function test_folder_picker_dialog() {
            var d = push(folderDialog)
            verify(d.selectedPath.length > 0) // home by default
            clickRow(d._list, 1) // Downloads
            verify(d.selectedPath.match(/\/Downloads$/), d.selectedPath)
            d.accept()
            tryCompare(win.pageStack, "depth", 1)
            verify(log[0].match(/\/Downloads$/), log[0])
        }

        function test_folder_picker_page() {
            var p = push(folderPage)
            compare(p.title, "Select location")
            compare(p.selectedPath, "")
            clickRow(p._list, 3) // Pictures
            tryCompare(win.pageStack, "depth", 3)
            var pictures = win.pageStack.currentPage
            compare(pictures._list.count, 1) // Camera
            pictures._select(pictures.path)
            tryCompare(win.pageStack, "depth", 1)
            verify(p.selectedPath.match(/\/Pictures$/), p.selectedPath)
        }

        function test_multi_content_dialog_lists_every_category() {
            var d = push(multiContent)
            tryCompare(d._model, "loading", false)
            compare(d._model.count, 9)
            compare(d.title, "")
        }

        function test_every_public_type_loads() {
            var o = createTemporaryObject(everyType, null)
            verify(o)
            compare(o.children[0].title, "Select document")
            compare(o.children[1].title, "Select document")
            compare(o.children[2].title, "Select music")
            compare(o.children[3].title, "Select video")
        }
    }
}
