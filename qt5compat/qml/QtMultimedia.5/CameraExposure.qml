// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.exposure (QtMultimedia 5.x). The Camera wrapper forwards
// exposureMode, exposureCompensation, manualIso and manualShutterSpeed to Qt 6's
// Camera. Metering and aperture are accepted and ignored (Qt 6 has no API for
// them). The ExposureMode and MeteringMode enums are on Camera, as in Qt 5.
import QtQml 2.15

QtObject {
    property int exposureMode: 0 // Camera.ExposureAuto
    property real exposureCompensation: 0
    property real manualIso: -1
    property real manualShutterSpeed: -1
    property real manualAperture: -1
    property int meteringMode: 1 // Camera.MeteringMatrix
    property point spotMeteringPoint: Qt.point(0.5, 0.5)
    readonly property real iso: __camera && __camera.__backend
                                ? __camera.__backend.qcam.isoSensitivity : -1
    readonly property real shutterSpeed: __camera && __camera.__backend
                                         ? __camera.__backend.qcam.exposureTime : -1
    readonly property real aperture: -1
    readonly property var supportedExposureModes: [0]

    property var __camera: null // the Camera wrapper

    function setAutoAperture() {
        manualAperture = -1
    }
    function setAutoIsoSensitivity() {
        manualIso = -1
    }
    function setAutoShutterSpeed() {
        manualShutterSpeed = -1
    }
}
