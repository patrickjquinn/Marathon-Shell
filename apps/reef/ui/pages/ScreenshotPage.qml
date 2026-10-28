// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// An app's screenshots full screen, as the Gallery shows a photo: swipe
// between them, tap to show or hide the close button and the count, and
// close with the button (or, with one screenshot, the usual back swipe:
// with several, a sideways swipe moves between them).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "screenshotPage"

    // Local file paths, in the order the listing shows them.
    property var paths: []
    property int startIndex: 0
    property bool chrome: true

    allowedOrientations: Orientation.All
    showNavigationIndicator: chrome
    backNavigation: paths.length < 2

    Rectangle {
        anchors.fill: parent
        color: Theme.darkPrimaryColor
    }

    SlideshowView {
        id: slides
        objectName: "screenshotSlides"
        // The neighbouring screenshots wait a page width to either side:
        // kept inside the page, so they do not slide over the page under it
        // as this one is pushed or popped.
        clip: true
        anchors.fill: parent
        itemWidth: width
        itemHeight: height
        model: page.paths
        currentIndex: page.startIndex

        delegate: MouseArea {
            id: slide
            required property string modelData
            width: slides.itemWidth
            height: slides.itemHeight
            onClicked: page.chrome = !page.chrome

            Image {
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall
                source: "file://" + slide.modelData
                sourceSize.width: page.width
                sourceSize.height: page.height
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: page.chrome ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { FadeAnimation {} }

        IconButton {
            id: close
            objectName: "closeScreenshots"
            // Clear of the top edge, where Lipstick takes touches for its
            // edge swipe: a tap there could miss the button.
            anchors {
                top: parent.top
                topMargin: Theme.itemSizeSmall
                right: parent.right
                rightMargin: Theme.paddingLarge
            }
            icon.source: "image://theme/icon-m-dismiss"
            onClicked: pageStack.pop()
        }

        Label {
            anchors {
                verticalCenter: close.verticalCenter
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
            }
            visible: page.paths.length > 1
            color: Theme.lightPrimaryColor
            font.pixelSize: Theme.fontSizeSmall
            text: qsTr("%1 of %2").arg(slides.currentIndex + 1).arg(page.paths.length)
        }
    }
}
