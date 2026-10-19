pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// The share sheet (ShareService): what is shared, and the apps that take it.
// A tap on one hands it over; a tap outside, a swipe down or back cancels.
Item {
    id: shareSheet

    property var request: null
    property bool shown: false
    property real dragOffset: 0
    readonly property var targets: request ? request.targets || [] : []

    signal chosen(string targetId)
    signal dismissed

    function open(next) {
        request = next;
        dragOffset = 0;
        shown = true;
    }

    function close(cancelled) {
        if (!shown)
            return;
        shown = false;
        dragOffset = 0;
        if (cancelled)
            dismissed();
    }

    anchors.fill: parent
    z: 2900
    visible: shown || panel.y < height

    Rectangle {
        objectName: "shareScrim"
        anchors.fill: parent
        color: "black"
        opacity: shareSheet.shown ? 0.5 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.durationFor("sheet")
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: shareSheet.shown
            onClicked: shareSheet.close(true)
        }
    }

    Item {
        id: panel

        objectName: "sharePanel"
        width: parent.width
        height: content.implicitHeight + Constants.navBarHeight + Silica.Theme.paddingLarge
        y: (shareSheet.shown ? parent.height - height : parent.height) + shareSheet.dragOffset
        clip: true

        // The ambience, as behind a Keel app's pages, under a hairline.
        KeelAmbienceBackground {
            width: shareSheet.width
            height: shareSheet.height
            y: -panel.y
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.3)
        }

        Behavior on y {
            enabled: !dragArea.drag.active

            NumberAnimation {
                duration: MMotion.durationFor("sheet")
                easing.type: MMotion.easingFor("sheet")
            }
        }

        MouseArea {
            id: dragArea

            property real startY: 0

            anchors.fill: parent
            onPressed: mouse => startY = mapToItem(shareSheet, mouse.x, mouse.y).y
            onPositionChanged: mouse => shareSheet.dragOffset = Math.max(0, mapToItem(shareSheet, mouse.x, mouse.y).y - startY)
            onReleased: {
                if (shareSheet.dragOffset > Silica.Theme.startDragDistance * 2)
                    shareSheet.close(true);
                else
                    shareSheet.dragOffset = 0;
            }
        }

        Column {
            id: content

            x: Silica.Theme.horizontalPageMargin
            y: Silica.Theme.paddingLarge
            width: parent.width - 2 * Silica.Theme.horizontalPageMargin
            spacing: Silica.Theme.paddingLarge

            Silica.Label {
                width: parent.width
                text: shareSheet.request && shareSheet.request.title ? shareSheet.request.title : qsTr("Share")
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeExtraLarge
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Row {
                width: parent.width
                spacing: Silica.Theme.paddingMedium
                visible: (shareSheet.request && !!shareSheet.request.image) || previewText.text !== ""

                Image {
                    id: preview

                    objectName: "sharePreviewImage"
                    width: visible ? Silica.Theme.itemSizeLarge : 0
                    height: width
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Silica.Theme.itemSizeLarge
                    sourceSize.height: Silica.Theme.itemSizeLarge
                    source: shareSheet.request && shareSheet.request.image ? shareSheet.request.image : ""
                    visible: shareSheet.request ? !!shareSheet.request.image : false
                    asynchronous: true
                }

                Silica.Label {
                    id: previewText

                    objectName: "sharePreviewText"
                    width: parent.width - (preview.visible ? preview.width + parent.spacing : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (!shareSheet.request)
                            return "";
                        if (shareSheet.request.text)
                            return shareSheet.request.text;
                        const count = shareSheet.request.count || 0;
                        return count > 1 ? qsTr("%n items", "", count) : "";
                    }
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            Silica.Label {
                objectName: "shareNoTargets"
                width: parent.width
                visible: shareSheet.targets.length === 0
                text: qsTr("No app can take this")
                color: Silica.Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter
            }

            Grid {
                id: grid

                readonly property real cellWidth: Math.floor(width / columns)

                width: parent.width
                columns: 4

                Repeater {
                    model: shareSheet.targets

                    delegate: Silica.BackgroundItem {
                        id: target

                        required property var modelData

                        objectName: "shareTarget-" + target.modelData.id
                        width: grid.cellWidth
                        height: targetColumn.implicitHeight + 2 * Silica.Theme.paddingMedium
                        Accessible.name: target.modelData.action ? target.modelData.action : target.modelData.name
                        onClicked: {
                            shareSheet.close(false);
                            shareSheet.chosen(target.modelData.id);
                        }

                        Column {
                            id: targetColumn

                            anchors.centerIn: parent
                            width: parent.width - Silica.Theme.paddingSmall * 2
                            spacing: Silica.Theme.paddingSmall

                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Silica.Theme.iconSizeLauncher
                                height: width

                                MAppIcon {
                                    anchors.fill: parent
                                    size: parent.width
                                    source: target.modelData.icon || ""
                                    visible: !target.modelData.glyph
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 4
                                    color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
                                    visible: !!target.modelData.glyph

                                    GlyphIcon {
                                        anchors.centerIn: parent
                                        name: target.modelData.glyph || ""
                                        size: Silica.Theme.iconSizeMedium
                                        color: Silica.Theme.primaryColor
                                    }
                                }
                            }

                            Silica.Label {
                                width: parent.width
                                text: target.modelData.action || target.modelData.name
                                color: target.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
