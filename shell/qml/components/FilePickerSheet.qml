pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// The file chooser (FileChooserPortal): an app's request to open files,
// save one, or pick a folder, laid out as a Marathon dialog. Back, Cancel
// or a swipe down on the header cancels.
Item {
    id: picker

    property var request: null
    property bool shown: false
    readonly property string ownerAppId: request ? request.appId || "" : ""
    readonly property bool ownerActive: ownerAppId === "" || UIStore.currentAppId === ownerAppId
    readonly property string mode: request ? request.mode : "open"
    readonly property bool saving: mode === "save"
    readonly property bool folderPick: request ? !!request.directory : false
    readonly property bool multiple: request ? !!request.multiple : false
    readonly property var filters: request ? request.filters || [] : []
    property int filterIndex: -1
    property var selection: []
    property var choiceValues: ({})
    property string name: ""
    property bool confirmReplace: false
    readonly property string savePath: name === "" ? "" : files.join(files.folder, name)
    readonly property bool imagesOnly: {
        const filter = filters[filterIndex];
        return !!filter && filter.globs.length === 0 && filter.mimes.length > 0 && filter.mimes.every(m => m.startsWith("image/"));
    }
    readonly property bool canAccept: folderPick || (saving ? name.trim() !== "" : selection.length > 0)
    readonly property real gutter: Silica.Theme.paddingSmall
    // Marathon glass needs a GPU renderer; the software one draws no shaders.
    readonly property bool glass: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property var placeGlyphs: ({
            "Home": "house",
            "Documents": "file-text",
            "Downloads": "download-simple",
            "Pictures": "image",
            "Music": "music-notes",
            "Videos": "film-strip",
            "Camera": "camera"
        })

    signal accepted(var paths, int filterIndex, var choices)
    signal cancelled

    function open(next) {
        request = next;
        filterIndex = next.filterIndex !== undefined ? next.filterIndex : -1;
        selection = [];
        name = next.name || "";
        confirmReplace = false;
        const values = {};
        for (const choice of next.choices || [])
            values[choice.id] = choice.value;
        choiceValues = values;
        searchField.text = "";
        files.recent = false;
        files.folder = next.folder && files.exists(next.folder) ? next.folder : defaultFolder();
        shown = true;
    }

    function defaultFolder() {
        const places = files.places();
        const wanted = imagesOnly ? "Pictures" : saving || folderPick ? "Documents" : "";
        const place = places.find(p => p.path.endsWith("/" + wanted));
        return place ? place.path : places[0].path;
    }

    // Portal labels use desktop mnemonic markers ("_Open", "&Save").
    // Marathon has no keyboard mnemonics, so displaying them is visual noise.
    function plainActionLabel(label) {
        return String(label || "").replace(/__(?=.)/g, "\u0000").replace(/_(?=.)/g, "").replace(/\u0000/g, "_").replace(/&&(?=.)/g, "\u0000").replace(/&(?=.)/g, "").replace(/\u0000/g, "&");
    }

    function close() {
        shown = false;
    }

    function cancel() {
        if (!shown)
            return;
        close();
        cancelled();
    }

    function finish(paths) {
        close();
        accepted(paths, filterIndex, choiceValues);
    }

    function acceptCurrent() {
        if (folderPick) {
            finish([files.folder]);
        } else if (saving) {
            if (files.exists(savePath) && !confirmReplace) {
                confirmReplace = true;
                return;
            }
            finish([savePath]);
        } else if (selection.length > 0) {
            finish(selection);
        }
    }

    function openEntry(path, isDir) {
        if (isDir) {
            searchField.text = "";
            files.recent = false;
            files.folder = path;
        } else if (saving) {
            name = path.substring(path.lastIndexOf("/") + 1);
        } else if (!folderPick && !multiple) {
            finish([path]);
        } else if (multiple) {
            const at = selection.indexOf(path);
            selection = at < 0 ? selection.concat([path]) : selection.filter(p => p !== path);
        }
    }

    function goUp() {
        const at = files.folder.lastIndexOf("/");
        if (at > 0)
            files.folder = files.folder.substring(0, at);
    }

    anchors.fill: parent
    z: 2950
    // A portal dialog belongs above the requesting app, not whichever task is
    // currently foreground. Keep the request alive but hide it while its owner
    // is away; it reappears when that task returns.
    visible: shown && ownerActive

    onNameChanged: confirmReplace = false

    FileChooserModel {
        id: files

        directoriesOnly: picker.folderPick
        nameFilters: picker.filters[picker.filterIndex] ? picker.filters[picker.filterIndex].globs : []
        mimeFilters: picker.filters[picker.filterIndex] ? picker.filters[picker.filterIndex].mimes : []
        search: searchField.text
    }

    MGlassBackdrop {
        id: glassBackdrop

        anchors.fill: parent
        visible: picker.shown && picker.glass
    }

    MGlassPlatter {
        objectName: "filePickerPanel"
        anchors.fill: parent
        visible: picker.glass
        backdrop: glassBackdrop.texture
        radius: 0
    }

    // Without glass, the ambience, as behind a Keel app's pages.
    KeelAmbienceBackground {
        anchors.fill: parent
        visible: picker.shown && !picker.glass
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
        brightest: AmbienceService.brightest
        darkest: AmbienceService.darkest
    }

    // Taps stay in the picker.
    MouseArea {
        anchors.fill: parent
    }

    Column {
        id: top

        width: parent.width
        topPadding: Constants.statusBarHeight

        // A swipe down on the header cancels.
        DragHandler {
            target: null
            yAxis.enabled: true
            xAxis.enabled: false
            onActiveChanged: if (!active && centroid.scenePosition.y - centroid.scenePressPosition.y > Silica.Theme.itemSizeLarge)
                picker.cancel()
        }

        // Marathon's dialog header: Cancel and the accept action as text.
        Item {
            width: parent.width
            height: Silica.Theme.itemSizeLarge

            Rectangle {
                anchors.fill: parent
                color: Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, 0.12)
            }

            Silica.BackgroundItem {
                id: cancelButton

                objectName: "filePickerCancel"
                width: parent.width / 2
                height: parent.height
                onClicked: picker.cancel()

                Silica.Label {
                    x: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x
                    text: qsTr("Cancel")
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    color: cancelButton.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    truncationMode: Silica.TruncationMode.Fade
                }
            }

            Silica.BackgroundItem {
                id: acceptButton

                readonly property string text: {
                    if (picker.confirmReplace)
                        return qsTr("Replace");
                    const label = picker.request && picker.request.acceptLabel ? picker.plainActionLabel(picker.request.acceptLabel) : picker.folderPick ? qsTr("Select") : picker.saving ? qsTr("Save") : qsTr("Open");
                    return picker.multiple && picker.selection.length > 0 ? qsTr("%1 (%2)").arg(label).arg(picker.selection.length) : label;
                }

                objectName: "filePickerAccept"
                anchors.right: parent.right
                width: parent.width / 2
                height: parent.height
                enabled: picker.canAccept
                onClicked: picker.acceptCurrent()

                Silica.Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - Silica.Theme.horizontalPageMargin)
                    horizontalAlignment: Text.AlignRight
                    text: acceptButton.text
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    color: !acceptButton.enabled ? Silica.Theme.secondaryColor : acceptButton.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    truncationMode: Silica.TruncationMode.Fade
                }
            }
        }

        Silica.Label {
            objectName: "filePickerTitle"
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            topPadding: Silica.Theme.paddingMedium
            bottomPadding: Silica.Theme.paddingMedium
            text: picker.request && picker.request.title ? picker.request.title : picker.folderPick ? qsTr("Choose a folder") : picker.saving ? qsTr("Save") : qsTr("Open")
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeExtraLarge
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // Places: Recent, Home and the media folders.
        ListView {
            id: placeList

            readonly property var entries: {
                const out = picker.folderPick ? [] : [{
                        "name": qsTr("Recent"),
                        "path": "",
                        "glyph": "clock-counter-clockwise"
                    }];
                for (const place of picker.shown ? files.places() : [])
                    out.push({
                        "name": place.name,
                        "path": place.path,
                        "glyph": picker.placeGlyphs[place.name] || "folder-simple"
                    });
                return out;
            }

            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            height: Silica.Theme.itemSizeLarge
            orientation: ListView.Horizontal
            clip: true
            spacing: Silica.Theme.paddingSmall
            boundsBehavior: Flickable.StopAtBounds
            model: entries

            footer: Item {
                width: Silica.Theme.horizontalPageMargin
                height: 1
            }

            delegate: Silica.BackgroundItem {
                id: place

                required property var modelData
                readonly property bool current: modelData.path === "" ? files.recent : !files.recent && files.folder === modelData.path

                objectName: "filePlace-" + modelData.name
                width: Math.max(Silica.Theme.itemSizeLarge, placeLabel.implicitWidth + 2 * Silica.Theme.paddingMedium)
                height: placeList.height
                highlighted: down || current
                Accessible.name: modelData.name
                onClicked: {
                    searchField.text = "";
                    if (modelData.path === "") {
                        files.recent = true;
                    } else {
                        files.recent = false;
                        files.folder = modelData.path;
                    }
                }

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: placeLabel.top
                    anchors.bottomMargin: Silica.Theme.paddingSmall
                    name: place.modelData.glyph
                    size: Silica.Theme.iconSizeMedium
                    color: place.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                }

                Silica.Label {
                    id: placeLabel

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Silica.Theme.paddingSmall
                    text: place.modelData.name
                    font.pixelSize: Silica.Theme.fontSizeTiny
                    color: place.highlighted ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
                }
            }
        }

        Silica.SearchField {
            id: searchField

            objectName: "filePickerSearch"
            width: parent.width
            placeholderText: qsTr("Search files")
            visible: !files.recent && !picker.folderPick
        }

        // The folder open, with Up.
        Silica.BackgroundItem {
            id: up

            objectName: "filePickerUp"
            width: parent.width
            height: Silica.Theme.itemSizeSmall
            visible: !files.recent && searchField.text === ""
            enabled: files.folder.lastIndexOf("/") > 0
            Accessible.name: qsTr("Up")
            onClicked: picker.goUp()

            GlyphIcon {
                id: upGlyph

                x: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                name: "arrow-up"
                size: Silica.Theme.iconSizeSmall
                color: up.enabled ? (up.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor) : Silica.Theme.secondaryColor
            }

            Silica.Label {
                objectName: "filePickerFolder"
                anchors.left: upGlyph.right
                anchors.leftMargin: Silica.Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: files.folder.substring(files.folder.lastIndexOf("/") + 1)
                color: Silica.Theme.highlightColor
                truncationMode: Silica.TruncationMode.Fade
            }
        }

        Flow {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            spacing: Silica.Theme.paddingSmall
            visible: picker.filters.length > 1

            Repeater {
                model: picker.filters

                delegate: Silica.FilterChip {
                    required property var modelData
                    required property int index

                    objectName: "fileFilter-" + index
                    text: modelData.name
                    automaticCheck: false
                    checked: picker.filterIndex === index
                    onClicked: picker.filterIndex = index
                }
            }
        }

        Repeater {
            model: picker.request ? picker.request.choices || [] : []

            delegate: Flow {
                id: choiceRow

                required property var modelData

                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                spacing: Silica.Theme.paddingSmall

                Silica.Label {
                    height: Silica.Theme.itemSizeExtraSmall
                    verticalAlignment: Text.AlignVCenter
                    text: choiceRow.modelData.label
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                }

                Repeater {
                    model: choiceRow.modelData.options.length > 0 ? choiceRow.modelData.options : [{
                            "id": "true",
                            "label": qsTr("On")
                        }]

                    delegate: Silica.FilterChip {
                        required property var modelData

                        objectName: "fileChoice-" + choiceRow.modelData.id + "-" + modelData.id
                        text: modelData.label
                        automaticCheck: false
                        checked: picker.choiceValues[choiceRow.modelData.id] === modelData.id
                        onClicked: {
                            const values = Object.assign({}, picker.choiceValues);
                            const boolean = choiceRow.modelData.options.length === 0;
                            values[choiceRow.modelData.id] = boolean && checked ? "false" : modelData.id;
                            picker.choiceValues = values;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: rowDelegate

        Silica.BackgroundItem {
            id: entry

            required property string name
            required property string path
            required property bool isDir
            required property bool isImage
            required property real size
            required property url url
            readonly property bool selected: picker.selection.indexOf(path) >= 0

            objectName: "fileEntry-" + name
            width: ListView.view.width
            height: Silica.Theme.itemSizeMedium
            highlighted: down || selected
            Accessible.name: name
            onClicked: picker.openEntry(path, isDir)

            Item {
                id: thumb

                x: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Silica.Theme.iconSizeMedium
                height: width

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: width
                    sourceSize.height: height
                    asynchronous: true
                    source: entry.isImage ? entry.url : ""
                    visible: entry.isImage
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    name: entry.isDir ? "folder" : "file"
                    size: Silica.Theme.iconSizeMedium
                    color: entry.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    visible: !entry.isImage
                }
            }

            Column {
                anchors.left: thumb.right
                anchors.leftMargin: Silica.Theme.paddingLarge
                anchors.right: check.left
                anchors.rightMargin: Silica.Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter

                Silica.Label {
                    width: parent.width
                    text: entry.name
                    color: entry.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    truncationMode: Silica.TruncationMode.Fade
                }

                Silica.Label {
                    width: parent.width
                    visible: !entry.isDir
                    text: Silica.Format.formatFileSize(entry.size)
                    color: entry.highlighted ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                }
            }

            GlyphIcon {
                id: check

                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                name: "check"
                size: Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
                visible: entry.selected
            }
        }
    }

    // Square tiles on one gutter: pictures cropped, folders a glyph and name.
    Component {
        id: tileDelegate

        Item {
            id: tile

            required property string name
            required property string path
            required property bool isDir
            required property bool isImage
            required property url url
            readonly property bool selected: picker.selection.indexOf(path) >= 0

            objectName: "fileEntry-" + name
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            Accessible.role: Accessible.Button
            Accessible.name: name

            Silica.BackgroundItem {
                id: tileBox

                anchors.fill: parent
                anchors.margins: picker.gutter / 2
                highlighted: down || tile.selected
                onClicked: picker.openEntry(tile.path, tile.isDir)

                Rectangle {
                    anchors.fill: parent
                    color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.06)
                    visible: !tile.isImage
                }

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: width
                    sourceSize.height: height
                    asynchronous: true
                    source: tile.isImage ? tile.url : ""
                    visible: tile.isImage
                    opacity: tile.selected ? 0.6 : 1
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Silica.Theme.paddingMedium
                    name: tile.isDir ? "folder" : "file"
                    size: Silica.Theme.iconSizeMedium
                    color: tileBox.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    visible: !tile.isImage
                }

                Silica.Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Silica.Theme.paddingSmall
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.name
                    font.pixelSize: Silica.Theme.fontSizeTiny
                    color: tileBox.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    truncationMode: Silica.TruncationMode.Fade
                    visible: !tile.isImage
                }

                GlyphIcon {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Silica.Theme.paddingSmall
                    name: "check-circle"
                    size: Silica.Theme.iconSizeSmall
                    color: Silica.Theme.highlightColor
                    visible: tile.selected
                }
            }
        }
    }

    Loader {
        id: content

        anchors.top: top.bottom
        anchors.topMargin: Silica.Theme.paddingSmall
        anchors.bottom: saveBar.visible ? saveBar.top : parent.bottom
        anchors.bottomMargin: saveBar.visible ? 0 : Constants.navBarHeight
        width: parent.width
        sourceComponent: picker.imagesOnly ? gridView : listView
    }

    Component {
        id: listView

        Silica.SilicaListView {
            objectName: "filePickerList"
            clip: true
            model: files
            delegate: rowDelegate

            Silica.ViewPlaceholder {
                enabled: files.count === 0
                text: searchField.text !== "" ? qsTr("Nothing found") : qsTr("No files here")
            }
        }
    }

    Component {
        id: gridView

        Silica.SilicaGridView {
            readonly property int columns: Math.max(3, Math.floor((width - 2 * leftMargin) / (Silica.Theme.itemSizeHuge * 0.75)))

            objectName: "filePickerGrid"
            clip: true
            model: files
            leftMargin: Silica.Theme.horizontalPageMargin - picker.gutter / 2
            rightMargin: leftMargin
            cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
            cellHeight: cellWidth
            delegate: tileDelegate

            Silica.ViewPlaceholder {
                enabled: files.count === 0
                text: searchField.text !== "" ? qsTr("Nothing found") : qsTr("No pictures here")
            }
        }
    }

    Column {
        id: saveBar

        anchors.bottom: parent.bottom
        anchors.bottomMargin: Constants.navBarHeight
        width: parent.width
        visible: picker.saving

        Silica.Label {
            objectName: "filePickerReplace"
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: picker.confirmReplace
            text: qsTr("“%1” is already there. Replace it?").arg(picker.name)
            color: Silica.Theme.errorColor
            wrapMode: Text.Wrap
            font.pixelSize: Silica.Theme.fontSizeSmall
        }

        Silica.TextField {
            id: nameField

            objectName: "filePickerName"
            width: parent.width
            label: qsTr("Name")
            text: picker.name
            inputMethodHints: Qt.ImhNoPredictiveText
            onTextChanged: picker.name = text
            Silica.EnterKey.enabled: picker.canAccept
            Silica.EnterKey.onClicked: picker.acceptCurrent()
        }
    }
}
