// SPDX-FileCopyrightText: 2013 - 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.1
import Sailfish.Silica 1.0
import Sailfish.Gallery 1.0
import MarathonApp.Camera 1.0

PagedView {
    id: root

    property alias overlay: overlay
    readonly property bool positionLocked: !overlay.active && playing

    readonly property bool active: page.galleryActive
    property QtObject captureModel

    property CameraPage page

    readonly property url source: currentItem ? currentItem.mediaUrl : ""
    readonly property bool playing: !!currentItem && !currentItem.isImage && !!currentItem.item && currentItem.item.playing
    property int _oldCount

    function _positionViewAtBeginning() {
        moveTo(0, PagedView.Immediate);
    }

    model: captureModel

    clip: true
    interactive: !positionLocked
    direction: PagedView.RightToLeft
    wrapMode: PagedView.NoWrap

    onActiveChanged: {
        if (!active) {
            if (overlay.remorse.active)
                overlay.remorse.trigger();
            overlay.active = Qt.binding(function () {
                return captureModel && captureModel.count > 0;
            });
        }
    }

    Connections {
        target: captureModel
        function onCountChanged() {
            if (captureModel.count === 0)
                page.returnToCaptureMode();
            // Move to the new added item if we are currently in the first one
            if (count > _oldCount && currentIndex === 1)
                _positionViewAtBeginning();
            _oldCount = count;
        }
    }

    delegate: Loader {
        readonly property int index: model.index
        // Not `source`: that is the Loader's own (an invalid override in Qt 6).
        readonly property url mediaUrl: model.fileUrl

        readonly property bool isImage: !/\.mp4$/i.test(model.fileName)
        readonly property bool error: !!item && !!item.error

        readonly property bool isCurrentItem: PagedView.isCurrentItem

        width: root.width
        height: root.height
        sourceComponent: isImage ? imageComponent : videoComponent
        asynchronous: !isCurrentItem

        Component {
            id: imageComponent

            ImageViewer {

                onZoomedChanged: overlay.active = !zoomed
                onClicked: {
                    if (zoomed) {
                        zoomOut();
                    } else {
                        overlay.active = !overlay.active;
                    }
                }

                source: parent.mediaUrl

                active: isCurrentItem && root.active
                viewMoving: root.moving
            }
        }

        Component {
            id: videoComponent

            // Its own controls; the roll's go while it plays.
            VideoPlayback {
                source: parent.mediaUrl
                onPlayingChanged: overlay.active = !playing
            }
        }
    }

    RollOverlay {
        id: overlay

        onRemove: {
            var item = currentItem;
            //: Delete an image
            remorseAction(qsTr("Deleting"), function () {
                root.captureModel.deleteFile(item.index);
            });
        }

        active: captureModel && captureModel.count > 0
        anchors.fill: parent
        source: root.source
        isImage: !root.currentItem || root.currentItem.isImage

        // The dismiss button (Silica's private DismissButton, written out
        // with public types).
        IconButton {
            y: Theme.paddingLarge
            anchors.right: parent.right
            anchors.rightMargin: Theme.horizontalPageMargin
            icon.source: "image://theme/icon-m-dismiss"
            onClicked: page.returnToCaptureMode()
        }
    }
}
