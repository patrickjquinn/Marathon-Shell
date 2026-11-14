// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// A Qt 6 app (`import QtMultimedia`, unversioned or 6.x) gets Qt 6's own
// QtMultimedia with the shims on the import path: Qt 6 Camera enums and
// CaptureSession, none of the Qt 5 names. Nothing is instantiated that needs
// a backend.
import QtQuick
import QtTest
import QtMultimedia

Item {
    MediaDevices { id: devices }

    Component {
        id: session
        CaptureSession {
            camera: Camera { }
            imageCapture: ImageCapture { }
        }
    }

    TestCase {
        name: "Qt6MultimediaUnaffected"

        function test_qt6_camera_type() {
            compare(session.status, Component.Ready)
            compare(Camera.FocusModeAuto, 0)
            compare(Camera.TorchOn, 1)
            // Qt 5 enum names (looked up by name: they do not exist here).
            for (var name of ["ActiveState", "FlashTorch", "FocusPointCustom"])
                compare(Camera[name], undefined, name)
            verify(Array.isArray(devices.videoInputs) || devices.videoInputs.length >= 0)
        }
        function test_no_qt5_names() {
            for (var src of ['import QtMultimedia; QtObject { property int v: QtMultimedia.availableCameras.length }',
                             'import QtMultimedia 6.0; QtObject { property var v: CameraImageProcessing.WhiteBalanceFlash }']) {
                var failed = false
                try {
                    var o = Qt.createQmlObject(src, this)
                    failed = o.v === undefined
                    o.destroy()
                } catch (e) {
                    failed = true
                }
                verify(failed, src)
            }
        }
    }
}
