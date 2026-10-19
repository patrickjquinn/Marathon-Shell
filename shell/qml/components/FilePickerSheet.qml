pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// The file chooser (FileChooserPortal): an app's request to open files,
// save one, or pick a folder. Back, Cancel or a swipe down cancels.
Item {
    id: picker

    property var request: null
    property bool shown: false
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
    visible: shown

    onNameChanged: confirmReplace = false

    FileChooserModel {
        id: files

        directoriesOnly: picker.folderPick
        nameFilters: picker.filters[picker.filterIndex] ? picker.filters[picker.filterIndex].globs : []
        mimeFilters: picker.filters[picker.filterIndex] ? picker.filters[picker.filterIndex].mimes : []
        search: searchField.text
    }

    Rectangle {
        objectName: "filePickerPanel"
        anchors.fill: parent
        color: MColors.background
        // Taps stay in the picker.
        MouseArea {
            anchors.fill: parent
        }
    }

    Column {
        id: top

        width: parent.width

        // A swipe down on the header cancels.
        DragHandler {
            target: null
            yAxis.enabled: true
            xAxis.enabled: false
            onActiveChanged: if (!active && centroid.scenePosition.y - centroid.scenePressPosition.y > Silica.Theme.itemSizeLarge)
                picker.cancel()
        }
        topPadding: Constants.statusBarHeight

        Item {
            width: parent.width
            height: Silica.Theme.itemSizeMedium

            Silica.Button {
                id: cancelButton

                objectName: "filePickerCancel"
                anchors.left: parent.left
                anchors.leftMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Cancel")
                onClicked: picker.cancel()
            }

            Silica.Label {
                anchors.left: cancelButton.right
                anchors.right: acceptButton.left
                anchors.margins: Silica.Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: picker.request && picker.request.title ? picker.request.title : picker.folderPick ? qsTr("Choose a folder") : picker.saving ? qsTr("Save") : qsTr("Open")
                color: Silica.Theme.highlightColor
                truncationMode: Silica.TruncationMode.Fade
            }

            Silica.Button {
                id: acceptButton

                objectName: "filePickerAccept"
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                enabled: picker.canAccept
                text: {
                    if (picker.confirmReplace)
                        return qsTr("Replace");
                    const label = picker.request && picker.request.acceptLabel ? picker.request.acceptLabel : picker.folderPick ? qsTr("Select") : picker.saving ? qsTr("Save") : qsTr("Open");
                    return picker.multiple && picker.selection.length > 0 ? label + " (" + picker.selection.length + ")" : label;
                }
                onClicked: picker.acceptCurrent()
            }
        }

        Flickable {
            width: parent.width
            height: Silica.Theme.itemSizeExtraSmall
            contentWidth: places.width + 2 * Silica.Theme.horizontalPageMargin
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
                id: places

                x: Silica.Theme.horizontalPageMargin
                spacing: Silica.Theme.paddingSmall

                Silica.FilterChip {
                    objectName: "filePlace-recent"
                    text: qsTr("Recent")
                    automaticCheck: false
                    checked: files.recent
                    visible: !picker.folderPick
                    onClicked: {
                        searchField.text = "";
                        files.recent = true;
                    }
                }

                Repeater {
                    model: picker.shown ? files.places() : []

                    delegate: Silica.FilterChip {
                        required property var modelData

                        objectName: "filePlace-" + modelData.name
                        text: modelData.name
                        automaticCheck: false
                        checked: !files.recent && files.folder === modelData.path
                        onClicked: {
                            searchField.text = "";
                            files.recent = false;
                            files.folder = modelData.path;
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: Silica.Theme.itemSizeSmall
            visible: !files.recent

            Silica.BackgroundItem {
                id: up

                objectName: "filePickerUp"
                anchors.left: parent.left
                anchors.leftMargin: Silica.Theme.horizontalPageMargin - Silica.Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                width: Silica.Theme.itemSizeSmall
                height: Silica.Theme.itemSizeSmall
                enabled: files.folder.lastIndexOf("/") > 0
                Accessible.name: qsTr("Up")
                onClicked: picker.goUp()

                GlyphIcon {
                    anchors.centerIn: parent
                    name: "arrow-up"
                    size: Silica.Theme.iconSizeSmall
                    color: up.enabled ? Silica.Theme.primaryColor : Silica.Theme.secondaryColor
                }
            }

            Silica.Label {
                objectName: "filePickerFolder"
                anchors.left: up.right
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: files.folder.substring(files.folder.lastIndexOf("/") + 1)
                truncationMode: Silica.TruncationMode.Fade
            }
        }

        Silica.SearchField {
            id: searchField

            objectName: "filePickerSearch"
            width: parent.width
            placeholderText: qsTr("Search")
            visible: !files.recent && !picker.folderPick
        }

        Row {
            x: Silica.Theme.horizontalPageMargin
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

            delegate: Row {
                id: choiceRow

                required property var modelData

                x: Silica.Theme.horizontalPageMargin
                spacing: Silica.Theme.paddingSmall

                Silica.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: choiceRow.modelData.label
                    color: Silica.Theme.secondaryColor
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
                anchors.leftMargin: Silica.Theme.paddingMedium
                anchors.right: check.left
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
                    color: Silica.Theme.secondaryColor
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

    Component {
        id: tileDelegate

        Silica.BackgroundItem {
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
            highlighted: down || selected
            Accessible.name: name
            onClicked: picker.openEntry(path, isDir)

            Image {
                anchors.fill: parent
                anchors.margins: 1
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: width
                sourceSize.height: height
                asynchronous: true
                source: tile.isImage ? tile.url : ""
                opacity: tile.selected ? 0.6 : 1
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Silica.Theme.paddingSmall * 2
                visible: !tile.isImage

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: tile.isDir ? "folder" : "file"
                    size: Silica.Theme.iconSizeMedium
                    color: Silica.Theme.primaryColor
                }

                Silica.Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.name
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    truncationMode: Silica.TruncationMode.Fade
                }
            }

            GlyphIcon {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Silica.Theme.paddingSmall
                name: "check"
                size: Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
                visible: tile.selected
            }
        }
    }

    Loader {
        id: content

        anchors.top: top.bottom
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
            objectName: "filePickerGrid"
            clip: true
            model: files
            cellWidth: width / Math.max(3, Math.floor(width / (Silica.Theme.itemSizeHuge)))
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

        Silica.Label {
            objectName: "filePickerReplace"
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * Silica.Theme.horizontalPageMargin
            visible: picker.confirmReplace
            text: qsTr("“%1” is already there. Replace it?").arg(picker.name)
            color: Silica.Theme.errorColor
            wrapMode: Text.Wrap
            font.pixelSize: Silica.Theme.fontSizeSmall
        }
    }
}
