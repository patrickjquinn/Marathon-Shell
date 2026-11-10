// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera under `import QtMultimedia 5.4`, used as foilauth's and
// yubikey's ScanPage/ViewFinder use it: a VideoOutput whose source is a
// Camera with grouped flash/exposure/focus/imageProcessing/videoRecorder
// settings, cameraState bound, imageCapture handlers, QtMultimedia
// .availableCameras. Runs without a camera device and without a Qt Multimedia
// backend: nothing may abort, availability is Unavailable, cameraStatus
// UnavailableStatus, and no Qt 6 VideoOutput or capture session is created.
// With a camera present the device-dependent checks are skipped.
import QtQuick 2.0
import QtTest 1.0
import QtMultimedia 5.4
import "../../qml/QtMultimedia.5/VideoGeometry.js" as Geometry

Item {
    id: root
    width: 200; height: 300

    property bool completed: true
    property bool tapFocus: false
    property int capturedCount: 0
    property int failedCount: 0

    VideoOutput {
        id: viewFinder
        anchors.fill: parent
        fillMode: VideoOutput.Stretch
        orientation: 90

        readonly property bool cameraActive: camera.cameraState === Camera.ActiveState
        readonly property bool flashOn: camera.flash.mode !== Camera.FlashOff

        source: Camera {
            id: camera

            flash.mode: Camera.FlashOff
            captureMode: Camera.CaptureVideo
            videoRecorder.frameRate: 30
            imageProcessing.whiteBalanceMode: viewFinder.flashOn ?
                CameraImageProcessing.WhiteBalanceFlash :
                CameraImageProcessing.WhiteBalanceTungsten
            cameraState: root.completed ? Camera.ActiveState : Camera.UnloadedState
            exposure {
                exposureCompensation: 1.0
                exposureMode: Camera.ExposureAuto
            }
            focus {
                focusMode: root.tapFocus ? Camera.FocusAuto : Camera.FocusContinuous
                focusPointMode: root.tapFocus ? Camera.FocusPointCustom : Camera.FocusPointAuto
            }
            imageCapture {
                onImageCaptured: root.capturedCount++
                onImageSaved: root.capturedCount++
                onCaptureFailed: root.failedCount++
            }
        }

        Repeater {
            id: zones
            model: camera.focus.focusZones
            delegate: Item { }
        }
        MouseArea { id: area; anchors.fill: parent }
    }

    VideoOutput {
        id: filtered
        filters: [ QtObject { } ]
    }

    SignalSpy { id: errorSpy; target: camera; signalName: "error" }

    TestCase {
        name: "QtMultimedia5Camera"
        when: windowShown

        readonly property bool noCamera: QtMultimedia.availableCameras.length === 0

        function test_enums() {
            compare(Camera.UnloadedState, 0)
            compare(Camera.LoadedState, 1)
            compare(Camera.ActiveState, 2)
            compare(Camera.UnavailableStatus, 0)
            compare(Camera.LoadedStatus, 4)
            compare(Camera.ActiveStatus, 8)
            compare(Camera.CaptureStillImage, 1)
            compare(Camera.CaptureVideo, 2)
            compare(Camera.Available, 0)
            compare(Camera.Unavailable, 1)
            compare(Camera.FrontFace, 2)
            compare(Camera.FlashAuto, 1)
            compare(Camera.FlashOff, 2)
            compare(Camera.FlashTorch, 32)
            compare(Camera.FocusAuto, 8)
            compare(Camera.FocusContinuous, 16)
            compare(Camera.FocusPointCustom, 3)
            compare(Camera.FocusAreaUnused, 1)
            compare(Camera.FocusAreaFocused, 3)
            compare(Camera.ExposureBarcode, 20)
            compare(Camera.MeteringSpot, 3)
            compare(Camera.Locked, 2)
            compare(CameraImageProcessing.WhiteBalanceTungsten, 5)
            compare(CameraImageProcessing.WhiteBalanceFlash, 7)
            compare(VideoOutput.Stretch, 0)
            compare(VideoOutput.PreserveAspectCrop, 2)
        }
        function test_settings_accepted() {
            compare(camera.flash.mode, Camera.FlashOff)
            compare(camera.captureMode, Camera.CaptureVideo)
            compare(camera.videoRecorder.frameRate, 30)
            compare(camera.imageProcessing.whiteBalanceMode, CameraImageProcessing.WhiteBalanceTungsten)
            camera.flash.mode = Camera.FlashTorch
            verify(viewFinder.flashOn)
            compare(camera.imageProcessing.whiteBalanceMode, CameraImageProcessing.WhiteBalanceFlash)
            camera.flash.mode = Camera.FlashOff
            compare(camera.exposure.exposureCompensation, 1.0)
            compare(camera.exposure.exposureMode, Camera.ExposureAuto)
            compare(camera.focus.focusMode, Camera.FocusContinuous)
            root.tapFocus = true
            compare(camera.focus.focusMode, Camera.FocusAuto)
            compare(camera.focus.focusPointMode, Camera.FocusPointCustom)
            camera.focus.customFocusPoint = Qt.point(0.25, 0.75)
            compare(camera.focus.customFocusPoint, Qt.point(0.25, 0.75))
            verify(camera.focus.isFocusModeSupported(Camera.FocusAuto))
            root.tapFocus = false
            compare(zones.count, 0)
            camera.viewfinder.resolution = Qt.size(1280, 720)
            compare(camera.viewfinder.resolution, Qt.size(1280, 720))
            camera.metaData.orientation = 90
            compare(camera.metaData.orientation, 90)
            camera.videoRecorder.record()
            compare(camera.videoRecorder.recorderState, CameraRecorder.StoppedState)
        }
        function test_state_and_methods_without_camera() {
            if (!noCamera)
                skip("a camera device is present")
            compare(camera.availability, Camera.Unavailable)
            compare(camera.cameraStatus, Camera.UnavailableStatus)
            // cameraState is the requested state, as in Qt 5.
            compare(camera.cameraState, Camera.ActiveState)
            verify(viewFinder.cameraActive)
            camera.stop()
            compare(camera.cameraState, Camera.LoadedState)
            camera.start()
            compare(camera.cameraState, Camera.ActiveState)
            compare(camera.cameraStatus, Camera.UnavailableStatus)
            camera.searchAndLock()
            compare(camera.lockStatus, Camera.Unlocked)
            camera.unlock()
            compare(camera.lockStatus, Camera.Unlocked)
            compare(camera.digitalZoom, 1.0)
            compare(camera.maximumDigitalZoom, 1.0)
            camera.digitalZoom = 2.0
            compare(camera.digitalZoom, 2.0)
            compare(camera.orientation, 0)
            compare(camera.deviceId, "")
            compare(camera.position, Camera.UnspecifiedPosition)
            compare(camera.supportedViewfinderResolutions(), [])
            compare(camera.supportedViewfinderFrameRateRanges(), [])
            compare(camera.errorCode, Camera.NoError)
            compare(errorSpy.count, 0)
            verify(!camera.imageCapture.ready)
            compare(camera.imageCapture.capture(), -1)
            compare(root.failedCount, 1)
            compare(root.capturedCount, 0)
            compare(camera.imageCapture.capturedImagePath, "")
        }
        function test_binding_survives_unchanged_start() {
            root.completed = true
            camera.start() // already Active: the app binding stays
            root.completed = false
            compare(camera.cameraState, Camera.UnloadedState)
            root.completed = true
            compare(camera.cameraState, Camera.ActiveState)
        }
        function test_video_output_without_camera() {
            if (!noCamera)
                skip("a camera device is present")
            // No Qt 6 VideoOutput while there is nothing to show.
            compare(viewFinder.__output, null)
            compare(camera.__videoOutput, null)
            compare(viewFinder.contentRect, Qt.rect(0, 0, 0, 0))
            compare(viewFinder.fillMode, VideoOutput.Stretch)
            compare(area.parent, viewFinder)
        }
        function test_available_cameras() {
            verify(Array.isArray(QtMultimedia.availableCameras))
            if (noCamera)
                compare(QtMultimedia.defaultCamera, null)
        }
        function test_filters_accepted() {
            compare(filtered.filters.length, 1)
        }
        function test_map_geometry() {
            var r = Qt.rect(10, 20, 100, 50)
            compare(Geometry.normalizedToItem(Qt.point(0.5, 0.5), r, 0), Qt.point(60, 45))
            // Rotated counter-clockwise: the source's top-left is bottom-left.
            compare(Geometry.normalizedToItem(Qt.point(0, 0), r, 90), Qt.point(10, 70))
            compare(Geometry.itemToNormalized(Qt.point(10, 70), r, 90), Qt.point(0, 0))
            compare(Geometry.normalizedToItem(Qt.point(0, 0), r, -90), Qt.point(110, 20))
            for (var o of [0, 90, 180, 270]) {
                var n = Geometry.itemToNormalized(Geometry.normalizedToItem(Qt.point(0.2, 0.7), r, o), r, o)
                fuzzyCompare(n.x, 0.2, 1e-9)
                fuzzyCompare(n.y, 0.7, 1e-9)
            }
            compare(Geometry.mapRect(Qt.rect(0, 0, 1, 1), function (p) {
                return Geometry.normalizedToItem(p, r, 90)
            }), r)
            // The wrapper's functions without a Qt 6 output (empty contentRect);
            // a real camera gives the output a frame.
            if (!noCamera)
                return
            compare(viewFinder.mapPointToSourceNormalized(Qt.point(5, 5)), Qt.point(0, 0))
            compare(viewFinder.mapRectToItem(Qt.rect(0, 0, 10, 10)), Qt.rect(0, 0, 0, 0))
        }
    }
}
