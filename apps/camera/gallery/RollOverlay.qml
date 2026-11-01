// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Share 1.0
import Marathon.Platform 1.0

// The camera roll's controls over a photo or video: delete, share and the
// Gallery app at the foot; the roll adds its own at the top. Shown while
// `active`.
Item {
    id: root

    property bool active: true
    property url source
    property bool isImage: true
    readonly property alias remorse: remorse

    signal remove

    function remorseAction(text, callback) {
        remorse.execute(text, callback);
    }

    opacity: active ? 1.0 : 0.0
    visible: opacity > 0.0
    Behavior on opacity {
        FadeAnimator {}
    }

    Rectangle {
        width: parent.width
        height: Theme.itemSizeLarge + Theme.paddingLarge
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.rgba(Theme.darkPrimaryColor, 0.5)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.itemSizeLarge + 2 * Theme.paddingLarge
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: Theme.rgba(Theme.darkPrimaryColor, 0.5)
            }
        }
    }

    Row {
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        spacing: Theme.paddingLarge * 2

        IconButton {
            objectName: "deleteButton"
            icon.source: "image://theme/icon-m-delete"
            Accessible.name: qsTr("Delete")
            onClicked: root.remove()
        }
        IconButton {
            objectName: "shareButton"
            visible: KeelShareService.available()
            icon.source: "image://theme/icon-m-share"
            Accessible.name: qsTr("Share")
            onClicked: share.trigger()
        }
        IconButton {
            objectName: "galleryButton"
            icon.source: "image://theme/icon-m-image"
            Accessible.name: qsTr("Open in Gallery")
            onClicked: Navigation.launchApp("gallery")
        }
    }

    RemorsePopup {
        id: remorse
    }

    ShareAction {
        id: share

        mimeType: root.isImage ? "image/jpeg" : "video/mp4"
        title: root.isImage ? qsTr("Share photo") : qsTr("Share video")
        resources: root.source.toString() !== "" ? [root.source] : []
    }
}
