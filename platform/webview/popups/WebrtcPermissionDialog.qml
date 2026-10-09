// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.0
import Sailfish.Silica 1.0

UserPromptDialog {
    id: dialog

    property alias devices: webrtc.devices
    property alias origin: webrtc.origin
    property alias rememberValue: webrtc.rememberValue
    property alias choices: webrtc.choices

    WebrtcPermissionInterface {
        id: webrtc

        anchors.fill: parent
        rememberValue: remember.checked

        //: Allow the server to use media devices
        //% "Allow"
        acceptText: qsTrId("sailfish_components_webview_popups-he-allow_media_devices")

        //: Deny the server access to media devices
        //% "Deny"
        cancelText: qsTrId("sailfish_components_webview_popups-he-deny_media_devices")

        readonly property var dictionary: {
            //% "Front camera"
            "secondary": qsTrId("sailfish_components_webview_popups-la-primary_camera"),
            //% "Rear camera"
            "primary": qsTrId("sailfish_components_webview_popups-la-secondary_camera"),
            //% "Integrated microphone"
            "Integrated microphone": qsTrId("sailfish_components_webview_popups-la-integrated_microphone")
        }

        function translate(word) {
            var translated = dictionary[word]
            return translated ? translated : word
        }

        UserPromptUi {
            anchors.fill: parent
            dialog: dialog
            popupInterface: webrtc

            Column {
                width: parent.width
                spacing: Theme.paddingMedium

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    Icon {
                        visible: "camera" in devices
                        source: "image://theme/icon-m-browser-camera"
                    }
                    Icon {
                        visible: "microphone" in devices
                        source: "image://theme/icon-m-browser-microphone"
                    }
                }

                Label {
                    id: title

                    wrapMode: Text.WordWrap
                    x: Theme.horizontalPageMargin
                    width: parent.width - x * 2
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontFamilyHeading
                    font.pixelSize: Theme.fontSizeHuge
                    color: Theme.highlightColor
                }

                Label {
                    id: label

                    wrapMode: Text.WordWrap
                    x: Theme.horizontalPageMargin
                    width: parent.width - x * 2
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.highlightColor
                }

                ComboBox {
                    visible: "camera" in devices

                    //% "Camera"
                    label: qsTrId("sailfish_components_webview_popups-la-webrtc_camera_title")

                    menu: ContextMenu {
                        Repeater {
                            model: devices["camera"]
                            delegate: MenuItem {
                                text: webrtc.translate(model.modelData)
                            }
                        }
                    }
                    onCurrentIndexChanged: choices["camera"] = currentIndex
                }

                ComboBox {
                    visible: "microphone" in devices

                    //% "Microphone"
                    label: qsTrId("sailfish_components_webview_popups-la-webrtc_microphone_title")

                    menu: ContextMenu {
                        Repeater {
                            model: devices["microphone"]
                            delegate: MenuItem {
                                text: webrtc.translate(model.modelData)
                            }
                        }
                    }
                    onCurrentIndexChanged: choices["microphone"] = currentIndex
                }

                TextSwitch {
                    id: remember

                    //: Remember decision for this site for later use
                    //% "Remember for this site"
                    text: qsTrId("sailfish_components_webview_popups-remember_for_site")
                }
            }

            Component.onCompleted: {
                if ("microphone" in devices && "camera" in devices) {
                    choices = {"microphone": 0, "camera": 0}
                    //% "Camera and microphone"
                    title.text = qsTrId("sailfish_components_webview_popups-la-webrtc_camera_microphone_title")
                    //: %1 is the site that wants to use camera and microphone
                    //% "Allow %1 to use your camera and microphone?"
                    label.text = qsTrId("sailfish_components_webview_popups-la-camera_microphone_request")
                                        .arg(origin)
                } else if ("microphone" in devices) {
                    choices = {"microphone": 0}
                    //% "Microphone"
                    title.text = qsTrId("sailfish_components_webview_popups-la-webrtc_microphone_title")
                    //: %1 is the site that wants to use the microphone
                    //% "Allow %1 to use your microphone?"
                    label.text = qsTrId("sailfish_components_webview_popups-la-microphone_request")
                                        .arg(origin)
                } else if ("camera" in devices) {
                    choices = {"camera": 0}
                    //% "Camera"
                    title.text = qsTrId("sailfish_components_webview_popups-la-webrtc_camera_title")
                    //: %1 is the site that wants to use the camera
                    //% "Allow %1 to use your camera?"
                    label.text = qsTrId("sailfish_components_webview_popups-la-camera_request")
                                        .arg(origin)
                } else {
                    // The requested permission set is empty or not supported
                    dialog.reject()
                }
            }
        }
    }
}
