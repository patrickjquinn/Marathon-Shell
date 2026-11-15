// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Mock of the web view's PermissionRequest.
import QtQuick

QtObject {
    enum Kind { Geolocation, Camera, Microphone, CameraAndMicrophone, ScreenCapture, Notifications, DeviceInfo, WebsiteDataAccess, PointerLock, MediaKeySystem, ClipboardRead, Other }
    property int kind: PermissionRequest.Geolocation
    property url origin
    property bool answered: false
    property bool allowed: false
    function allow() { allowed = true; answered = true }
    function deny() { allowed = false; answered = true }
}
