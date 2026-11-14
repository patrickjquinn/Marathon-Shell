// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.flash (QtMultimedia 5.x). The Camera wrapper turns `mode` into
// Qt 6's flashMode and torchMode (FlashTorch and FlashVideoLight are the torch).
// The FlashMode enum is on Camera, as in Qt 5.
import QtQml 2.15

QtObject {
    property int mode: 2 // Camera.FlashOff
    readonly property bool ready: false
    readonly property var supportedModes: [2]
}
