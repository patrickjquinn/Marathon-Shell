// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5's `QtMultimedia` singleton (QtMultimedia 5.4): availableCameras and
// defaultCamera, from Qt 6's MediaDevices. Each entry has deviceId,
// displayName, position and orientation, as in Qt 5. Not kept:
// convertVolume() (Qt 6 has no QML equivalent; no corpus app uses it).
pragma Singleton
import QtQml 2.15
import QtMultimedia 6.0 as QM
import "CameraUtils.js" as Utils

QtObject {
    readonly property QM.MediaDevices __devices: QM.MediaDevices { }

    readonly property var availableCameras: Utils.inputs(__devices).map(Utils.describe)
    readonly property var defaultCamera: {
        var d = Utils.pick(__devices, "", 0)
        return d ? Utils.describe(d) : null
    }
}
