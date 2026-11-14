// SPDX-FileCopyrightText: 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
import QtQml 2.0

QtObject {
    property var contextMenu: ({"type": "item", "component": "ContextMenu.qml" })
    property var alertPopup: ({"type": "dialog", "component": "AlertDialog.qml" })
    property var confirmPopup: ({"type": "dialog", "component": "ConfirmDialog.qml" })
    property var promptPopup: ({"type": "dialog", "component": "PromptDialog.qml" })
    property var authPopup: ({"type": "dialog", "component": "AuthDialog.qml" })
    property var passwordManagerPopup: ({"type": "dialog", "component": "PasswordManagerDialog.qml" })
    property var locationPermissionPopup: ({"type": "dialog", "component": "LocationDialog.qml" })
    property var webrtcPermissionPopup: ({"type": "dialog", "component": "WebrtcPermissionDialog.qml"})
    property var blockedTabPopup: ({"type": "dialog", "component": "BlockedTabPopupDialog.qml"})
    property var selectorPopup: ({"type": "dialog", "component": "SelectorDialog.qml"})
}
