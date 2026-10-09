// SPDX-FileCopyrightText: 2013 - 2020 Jolla Ltd
// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2013 - 2020 Jolla Ltd.
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import Sailfish.WebView.Popups 1.0

ContextMenuInterface {
    id: root

    readonly property bool active: visible
    readonly property bool landscape: width > height

    readonly property string url: !isJavascriptFunction ? linkHref : ""
    readonly property bool knownPlatformProtocol: isMailto || isTel || isSMS || isGeo
    readonly property bool isJavascriptFunction: linkProtocol === "javascript"

    // Image has source. That can be used to distinguish from other links.
    readonly property bool isImage: !isJavascriptFunction && imageSrc.length > 0

    // All elements are considered as links.
    readonly property bool isLink: !isJavascriptFunction && linkHref.length > 0

    // Separate hyper text links from other content types.
    readonly property bool isHyperTextLink: linkProtocol === "http"
                                            || linkProtocol === "https"
                                            || linkProtocol === "file"

    // Known platfrom content types.
    readonly property bool isMailto: linkProtocol === "mailto"
    readonly property bool isTel: linkProtocol === "tel"
    readonly property bool isSMS: linkProtocol === "sms"
    readonly property bool isGeo: linkProtocol === "geo"
    readonly property bool isNavigable: isLink && !knownPlatformProtocol

    width: parent.width
    height: parent.height
    visible: opacity > 0.0
    opacity: 0.0
    Behavior on opacity { FadeAnimation { duration: 300 } }

    function show() {
        opacity = 1.0
    }

    function _hide() {
        opacity = 0.0
        expander.open = false
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.highlightDimmerColor }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightDimmerColor, .91) }
        }

        SilicaFlickable {
            anchors.fill: parent
            contentHeight: content.height

            VerticalScrollDecorator {}

            Column {
                id: content

                width: parent.width
                topPadding: Theme.paddingLarge*2
                bottomPadding: Theme.paddingLarge
                spacing: Theme.paddingMedium

                Expander {
                    id: expander

                    horizontalMargin: Theme.horizontalPageMargin
                    width: parent.width
                    collapsedHeight: title.y + Math.min(title.height, 4 * fontMetrics.height)
                    expandedHeight: title.y + title.height + Theme.paddingLarge + Theme.paddingMedium

                    FontMetrics {
                        id: fontMetrics
                        font: title.font
                    }

                    Label {
                        id: title

                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.linkTitle || root.url
                        text: root.linkTitle || root.url
                        width: root.width - Theme.horizontalPageMargin*2
                        wrapMode: Text.Wrap
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        horizontalAlignment: Text.AlignHCenter
                        opacity: Theme.opacityHigh

                        MouseArea {
                            enabled: !expander.expandable
                            anchors {
                                fill: parent
                                topMargin: -content.anchors.topMargin
                                leftMargin: -Theme.horizontalPageMargin
                                rightMargin: -Theme.horizontalPageMargin
                                bottomMargin: -Theme.paddingMedium
                            }

                            onClicked: root._hide()
                        }
                    }
                }

                Label {
                    id: imageTitle

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text !== title.text
                    color: Theme.highlightColor
                    text: root.imageSrc.length > 0 ? root.imageSrc : root.url
                    width: root.width - Theme.horizontalPageMargin*2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: landscape ? 1 : 4
                    font.pixelSize: title.visible ? Theme.fontSizeMedium : Theme.fontSizeExtraLarge
                    horizontalAlignment: Text.AlignHCenter
                    opacity: Theme.opacityHigh

                    MouseArea {
                        anchors {
                            fill: parent
                            leftMargin: -Theme.horizontalPageMargin
                            rightMargin: -Theme.horizontalPageMargin
                            bottomMargin: -Theme.paddingMedium
                        }

                        onClicked: root._hide()
                    }
                }

                // Padding between titles and menu.
                MouseArea {
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: -Theme.horizontalPageMargin
                        rightMargin: -Theme.horizontalPageMargin
                    }

                    height: Math.max(Theme.itemSizeSmall - 2*content.spacing,
                                     root.height - y - content.spacing - menu.height - content.bottomPadding)

                    onClicked: root._hide()
                }

                Column {
                    id: menu

                    width: parent.width

                    ContextMenuItem {
                        visible: !isHyperTextLink && !isImage
                        text: {
                            if (isMailto) {
                                //% "Write email"
                                return qsTrId("sailfish_components_webview_popups-me-write-email")
                            } else if (isTel) {
                                //: Call, context of calling via voice call
                                //% "Call"
                                return qsTrId("sailfish_components_webview_popups-me-call")
                            } else if (isSMS) {
                                //: Send message (sms)
                                //% "Send message"
                                return qsTrId("sailfish_components_webview_popups-me-send-message")
                            } else {
                                //: Open link in current tab
                                //% "Open link"
                                return qsTrId("sailfish_components_webview_popups-me-open_link")
                            }
                        }
                        onClicked: {
                            root._hide()
                            Qt.openUrlExternally(root.linkHref)
                        }
                    }

                    ContextMenuItem {
                        visible: root.isNavigable && !!tabModel
                        //: Open link in a new tab from browser context menu
                        //% "Open link in a new tab"
                        text: qsTrId("sailfish_components_webview_popups-me-open_link_in_new_tab")
                        onClicked: {
                            root._hide()
                            tabModel.newTab(root.linkHref, root.linkTitle)
                        }
                    }

                    ContextMenuItem {
                        visible: root.isLink
                        //: Share link from browser context menu
                        //% "Share"
                        text: qsTrId("sailfish_components_webview_popups-me-share_link")
                        onClicked: {
                            root._hide()
                            webShareAction.shareLink(root.linkHref, root.linkTitle)
                        }
                        WebShareAction {
                            id: webShareAction
                        }
                    }

                    ContextMenuItem {
                        visible: root.url
                        //: Copy link to clipboard from context menu
                        //% "Copy link"
                        text: qsTrId("sailfish_components_webview_popups-me-copy_link_to_clipboard")
                        onClicked: {
                            root._hide()
                            Clipboard.text = root.url
                        }
                    }

                    ContextMenuItem {
                        visible: !root.isImage && root.linkTitle && (root.linkTitle != root.url)
                        //: Copy text to clipboard from context menu
                        //% "Copy text"
                        text: qsTrId("sailfish_components_webview_popups-me-copy_text_to_clipboard")
                        onClicked: {
                            root._hide()
                            Clipboard.text = root.linkTitle
                        }
                    }

                    DownloadMenuItem {
                        visible: root.downloadsEnabled && root.isNavigable
                        //% "Save link"
                        text: qsTrId("sailfish_components_webview_popups-me-save_link")
                        targetDirectory: StandardPaths.download
                        linkUrl: root.linkHref
                        contentType: root.contentType
                        viewId: root.viewId
                        onClicked: root._hide()
                    }

                    ContextMenuItem {
                        visible: root.isImage && !!tabModel
                        //% "Open image in a new tab"
                        text: qsTrId("sailfish_components_webview_popups-me-open_image_in_new_tab")
                        onClicked: {
                            root._hide()
                            tabModel.newTab(root.imageSrc, "")
                        }
                    }

                    DownloadMenuItem {
                        visible: root.isImage
                        //: This menu item saves image to Gallery application
                        //% "Save image"
                        text: qsTrId("sailfish_components_webview_popups-me-save_image")
                        targetDirectory: StandardPaths.download
                        linkUrl: root.imageSrc
                        contentType: root.contentType
                        viewId: root.viewId
                        onClicked: root._hide()
                    }

                    ContextMenuItem {
                        visible: root.isImage
                        //: Share image from context menu
                        //% "Share image"
                        text: qsTrId("sailfish_components_webview_popups-me-share_image")
                        onClicked: {
                            root._hide()
                            webShareAction.shareLink(root.imageSrc, root.url,
                                                     qsTrId("sailfish_components_webview_popups-me-share_image"))
                        }
                    }

                    ContextMenuItem {
                        visible: root.isImage
                        //: Copy image link clipboard from context menu
                        //% "Copy image link"
                        text: qsTrId("sailfish_components_webview_popups-me-copy_image_link_to_clipboard")
                        onClicked: {
                            root._hide()
                            Clipboard.text = root.imageSrc
                        }
                    }
                }
            }
        }
    }
}
