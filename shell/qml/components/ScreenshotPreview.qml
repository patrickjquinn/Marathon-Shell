import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: screenshotPreview

    property bool showing: false
    property string filePath: ""
    property string thumbnailPath: ""

    function show(path, thumbPath) {
        filePath = path;
        thumbnailPath = thumbPath;
        showing = true;
        slideIn.start();
        autoHideTimer.restart();
    }

    function hide() {
        slideOut.start();
    }

    function openInGallery() {
        Logger.info("ScreenshotPreview", "Opening screenshot in gallery: " + filePath);
        hide();
        NavigationRouter.navigateToDeepLink("gallery", "/image", {
            "path": filePath
        });
    }

    anchors.fill: parent
    z: 2700

    Rectangle {
        id: previewCard

        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: Constants.navBarHeight + Constants.bottomBarHeight + Silica.Theme.paddingLarge
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        width: Math.round(parent.width / 4) + Silica.Theme.paddingMedium * 2
        height: thumb.height + caption.height + Silica.Theme.paddingMedium * 2 + Silica.Theme.paddingSmall
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        visible: screenshotPreview.showing
        opacity: 0
        Accessible.role: Accessible.Button
        Accessible.name: caption.text
        //: Accessible description of the screenshot preview
        Accessible.description: qsTr("Opens in Gallery")
        Accessible.onPressAction: screenshotPreview.openInGallery()

        Column {
            anchors.fill: parent
            anchors.margins: Silica.Theme.paddingMedium
            spacing: Silica.Theme.paddingSmall

            Rectangle {
                id: thumb
                width: parent.width
                height: Math.round(width * screenshotPreview.height / Math.max(1, screenshotPreview.width))
                radius: Silica.Theme.paddingSmall / 2
                color: "black"
                clip: true

                Image {
                    anchors.fill: parent
                    source: screenshotPreview.thumbnailPath || ""
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    cache: false
                }
            }

            Silica.Label {
                id: caption
                text: qsTr("Screenshot saved")
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeTiny
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        MouseArea {
            property real startX: 0
            property bool swiped: false

            anchors.fill: parent
            onClicked: {
                if (!swiped)
                    screenshotPreview.openInGallery();
            }
            onPressed: mouse => {
                startX = mouse.x;
                swiped = false;
            }
            onPositionChanged: mouse => {
                if (!swiped && mouse.x - startX > Silica.Theme.paddingLarge * 2) {
                    swiped = true;
                    screenshotPreview.hide();
                }
            }
        }
    }

    NumberAnimation {
        id: slideIn

        target: previewCard
        property: "opacity"
        from: 0
        to: 1
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut

        target: previewCard
        property: "opacity"
        to: 0
        duration: 200
        easing.type: Easing.InCubic
        onFinished: {
            screenshotPreview.showing = false;
        }
    }

    Timer {
        id: autoHideTimer

        interval: 3000
        onTriggered: screenshotPreview.hide()
    }

    Rectangle {
        id: flashOverlay

        anchors.fill: parent
        color: "#FFFFFF"
        opacity: 0
        z: 3100

        SequentialAnimation {
            id: flashAnimation

            NumberAnimation {
                target: flashOverlay
                property: "opacity"
                to: 0.8
                duration: 50
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: flashOverlay
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.InCubic
            }
        }
    }

    Connections {
        function onScreenshotCaptured(path, image) {
            flashAnimation.start();
            var thumbUri = image.startsWith("file://") ? image : ("file://" + image);
            screenshotPreview.show(path, thumbUri);
        }

        target: ScreenshotService
    }
}
