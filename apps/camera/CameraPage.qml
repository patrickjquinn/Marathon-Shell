// SPDX-FileCopyrightText: 2013 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import QtQml.Models 2.1
import Nemo.KeepAlive 1.2
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

Page {
    id: page

    property alias viewfinder: captureView.viewfinder
    // For the app's Keel Actions and back handling.
    readonly property alias captureView: captureView
    property bool galleryActive
    property url galleryView
    readonly property bool captureModeActive: switcherView.currentIndex === 1
    readonly property bool galleryVisible: galleryLoader.visible
    readonly property int galleryIndex: galleryLoader.item ? galleryLoader.item.currentIndex : 0
    readonly property QtObject captureModel: galleryLoader.item ? galleryLoader.item.captureModel : null

    function resetZoom() {
        switcherView.resetZoom();
    }

    function returnToCaptureMode() {
        switcherView.returnToCaptureMode();
    }

    palette.colorScheme: Theme.LightOnDark

    _opaqueBackground: true

    allowedOrientations: captureView.inButtonLayout ? page.orientation : Orientation.All
    cutoutMode: CutoutMode.FullScreen

    Item {
        parent: page.parent

        width: page.width
        height: page.height
        rotation: page.rotation

        anchors.centerIn: parent
        z: -1

        Rectangle {
            x: galleryItem.x
            y: galleryItem.y
            width: galleryItem.width
            height: galleryItem.height
            color: "black"
            visible: switcherView.moving || galleryItem.PagedView.isCurrentItem
        }
    }

    PagedView {
        id: switcherView

        readonly property bool transitioning: moving || returnToCaptureModeTimeout.running

        function resetZoom() {
            captureView.camera.digitalZoom = 1.0;
        }

        function returnToCaptureMode() {
            if (__silica_applicationwindow_instance.applicationActive) {
                if (pageStack.currentPage === page) {
                    returnToCaptureModeTimeout.restart();
                    switcherView.currentIndex = 1;
                }
            } else {
                pageStack.pop(page, PageStackAction.Immediate);
                moveTo(1, PagedView.Immediate);
            }
        }

        Timer {
            id: returnToCaptureModeTimeout

            interval: 300 //switcherView.highlightMoveDuration
        }

        width: page.width
        height: page.height
        wrapMode: PagedView.NoWrap

        interactive: (!galleryLoader.item || !galleryLoader.item.positionLocked) && !captureView.recording
        currentIndex: 1
        focus: true

        Keys.onPressed: function (event) {
            if (!event.isAutoRepeat && event.key == Qt.Key_Camera) {
                switcherView.returnToCaptureMode();
            }
        }

        model: ObjectModel {
            Item {
                id: galleryItem

                width: page.width
                height: page.height

                Loader {
                    id: galleryLoader

                    anchors.fill: parent

                    asynchronous: true
                    visible: switcherView.moving || page.galleryActive || returnToCaptureModeTimeout.running
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Large
                    running: galleryLoader.status == Loader.Loading
                }
            }

            CaptureView {
                id: captureView

                readonly property real _viewfinderPosition: orientation == Orientation.Portrait || orientation == Orientation.Landscape ? parent.x + x : -parent.x - x
                width: page.width
                height: page.height

                active: true

                orientation: page.orientation
                pageRotation: page.rotation
                captureModel: page.captureModel
                orientationTransitionRunning: page.orientationTransitionRunning

                visible: switcherView.moving || captureView.active

                onLoaded: {
                    if (galleryLoader.source.toString() === "") {
                        galleryLoader.setSource(galleryView, {
                            page: page
                        });
                    }
                }

                CameraRollHint {
                    z: 2
                }
                CameraModeHint {
                    z: 2
                }

                Binding {
                    target: captureView.viewfinder
                    property: "x"
                    value: captureView.isPortrait ? captureView._viewfinderPosition : 0
                }

                Binding {
                    target: captureView.viewfinder
                    property: "y"
                    value: !captureView.isPortrait ? captureView._viewfinderPosition + (page.orientation == Orientation.Landscape ? captureView.viewfinderOffset : -captureView.viewfinderOffset) : (page.orientation == Orientation.Portrait ? captureView.viewfinderOffset : -captureView.viewfinderOffset)
                }
            }
        }

        onCurrentItemChanged: {
            if (!transitioning) {
                page.galleryActive = galleryItem.PagedView.isCurrentItem;
                captureView.active = captureView.PagedView.isCurrentItem;
            }
        }

        onTransitioningChanged: {
            if (!transitioning) {
                page.galleryActive = galleryItem.PagedView.isCurrentItem;
                captureView.active = captureView.PagedView.isCurrentItem;
            } else if (captureView.active) {
                if (galleryLoader.source.toString() === "") {
                    galleryLoader.setSource("gallery/GalleryView.qml", {
                        page: page
                    });
                } else if (galleryLoader.item) {
                    galleryLoader.item._positionViewAtBeginning();
                }
            }
        }
    }

    DisplayBlanking {
        preventBlanking: (galleryLoader.item && galleryLoader.item.playing) || captureView.camera.videoRecorder.recorderState == CameraRecorder.RecordingState
    }
}
