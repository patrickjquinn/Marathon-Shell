// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Helpers shared by the Qt 5 Camera wrappers: Qt 6 camera devices (QML
// cameraDevice values) as Qt 5 describes cameras.
.pragma library

// Qt 6 gives a device id as an ArrayBuffer (QByteArray); Qt 5 used a string.
function idString(device) {
    if (!device)
        return ""
    var id = device.id
    if (typeof id === "string")
        return id
    var bytes = new Uint8Array(id)
    var s = ""
    for (var i = 0; i < bytes.length; ++i)
        s += String.fromCharCode(bytes[i])
    return s
}

// Sensor mounting angle. Qt 6.7 added cameraDevice.correctionAngle; older
// Qt 6 does not know it, and Qt 5 reported 0 when the backend did not either.
function orientation(device) {
    if (!device || device.correctionAngle === undefined)
        return 0
    return Number(device.correctionAngle) || 0
}

function inputs(mediaDevices) {
    var list = mediaDevices ? mediaDevices.videoInputs : null
    var out = []
    if (list) {
        for (var i = 0; i < list.length; ++i)
            out.push(list[i])
    }
    return out
}

// Qt 5 QtMultimedia.availableCameras entry.
function describe(device) {
    return {
        deviceId: idString(device),
        displayName: device.description,
        position: device.position,
        orientation: orientation(device)
    }
}

// The device a Qt 5 Camera means: its deviceId if set, else the first device
// at its position (BackFace 1, FrontFace 2; Qt 5 and Qt 6 agree), else the
// default one. null when there is no camera.
function pick(mediaDevices, deviceId, position) {
    var list = inputs(mediaDevices)
    if (list.length === 0)
        return null
    var i
    if (deviceId !== "") {
        for (i = 0; i < list.length; ++i) {
            if (idString(list[i]) === deviceId)
                return list[i]
        }
    }
    if (position !== 0) {
        for (i = 0; i < list.length; ++i) {
            if (list[i].position === position)
                return list[i]
        }
    }
    var def = mediaDevices.defaultVideoInput
    return def && idString(def) !== "" ? def : list[0]
}
