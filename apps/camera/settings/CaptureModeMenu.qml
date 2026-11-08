// SPDX-FileCopyrightText: 2016 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

ExpandingMenu {
    // The photo and video pair, as the Jolla Camera shows it
    // (photo above, video below), once the camera records video. Until then
    // there is nothing to switch to, so the switch is not shown: a dimmed
    // video button that does nothing, or the photo icon alone (it looked
    // like an empty camera-roll thumbnail), only invites a tap. The
    // overlay's instance hides it (SettingsOverlay.qml).
    model: ["image", "video"]
    delegate: ExpandingMenuItem {
        objectName: modelData + "Mode"
        settings: Settings.global
        property: "captureMode"
        value: modelData
        icon: Settings.captureModeIcon(modelData)
        enabled: modelData !== "video" || CameraConfigs.supportedVideoResolutions.length > 0
        opacity: enabled ? 1.0 : Theme.opacityLow
    }
}
