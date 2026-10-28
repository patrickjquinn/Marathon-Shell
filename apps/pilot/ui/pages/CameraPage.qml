// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// The viewfinder for a camera turn (spec section 6.2, camera.capture:
// user-initiated only). Nothing is captured until the shutter is pressed;
// the photo goes to the app's cache, Pilot.look scales it down, sends it
// without metadata and deletes it, and the answer arrives on the main page.

import QtQuick
import QtMultimedia
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Page {
    id: page
    objectName: "cameraPage"
    allowedOrientations: Orientation.Portrait

    property string question: ""

    CaptureSession {
        camera: Camera { id: camera; active: page.status === PageStatus.Active }
        imageCapture: ImageCapture {
            id: capture
            onImageSaved: function(requestId, path) {
                Pilot.look(questionField.text, path)
                pageStack.pop()
            }
            onErrorOccurred: function(requestId, error, message) { status.text = message }
        }
        videoOutput: viewfinder
    }

    VideoOutput {
        id: viewfinder
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    Column {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: Theme.paddingLarge
        spacing: Theme.paddingMedium

        Label {
            id: status
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            text: camera.errorString
        }
        TextField {
            id: questionField
            objectName: "questionField"
            width: parent.width
            text: page.question
            placeholderText: qsTr("What should Pilot look for?")
            label: qsTr("Question")
            // The question is ready: close the keyboard, the shutter asks.
            EnterKey.iconSource: "image://theme/icon-m-enter-close"
            EnterKey.onClicked: questionField.focus = false
        }
        IconButton {
            objectName: "shutter"
            anchors.horizontalCenter: parent.horizontalCenter
            icon.source: "image://theme/icon-camera-shutter"
            enabled: capture.readyForCapture && !Pilot.busy
            onClicked: capture.captureToFile(Pilot.photoPath())
        }
    }
}
