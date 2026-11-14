// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.metaData (QtMultimedia 5.x): the image metadata an app sets
// before a capture. Accepted and ignored: the Qt 6 ImageCapture does not get
// them, so photos carry no app-set EXIF orientation, GPS or camera fields.
import QtQml 2.15

QtObject {
    property var cameraManufacturer
    property var cameraModel
    property var event
    property var subject
    property var orientation
    property var dateTimeOriginal
    property var gpsLatitude
    property var gpsLongitude
    property var gpsAltitude
    property var gpsTimestamp
    property var gpsTrack
    property var gpsSpeed
    property var gpsImgDirection
    property var gpsProcessingMethod
}
