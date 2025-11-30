import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: screenshotPreview
    anchors.fill: parent
    z: 2700

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

    Rectangle {
        id: previewCard
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: Constants.navBarHeight + Constants.bottomBarHeight + 16
        anchors.rightMargin: Constants.spacingMedium
        width: Math.round(160 * Constants.scaleFactor)
        height: Constants.touchTargetLarge
        radius: Constants.borderRadiusSmall
        color: Qt.rgba(15, 15, 15, 0.98)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.15)
        layer.enabled: true
        visible: showing
        opacity: 0

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.05)
        }

        Column {
            anchors.fill: parent
            anchors.margins: Math.round(8 * Constants.scaleFactor)
            spacing: Math.round(6 * Constants.scaleFactor)

            Rectangle {
                width: parent.width
                height: parent.height - Math.round(20 * Constants.scaleFactor)
                radius: Math.round(2 * Constants.scaleFactor)
                color: "#000000"
                clip: true

                Image {
                    anchors.fill: parent
                    source: thumbnailPath || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    cache: false
                }
            }

            Text {
                text: "Screenshot saved"
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeXSmall
                font.family: MTypography.fontFamily
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                Logger.info("ScreenshotPreview", "Opening screenshot in gallery: " + filePath);
                hide();

                // Deep link to gallery app with the screenshot
                if (typeof DeepLinkHandler !== 'undefined') {
                    DeepLinkHandler.handleDeepLink("gallery", "/image", {
                        path: filePath
                    });
                } else {
                    Logger.warn("ScreenshotPreview", "DeepLinkHandler not available");
                }
            }

            property real startX: 0

            onPressed: mouse => {
                startX = mouse.x;
            }

            onPositionChanged: mouse => {
                if (mouse.x - startX > 50) {
                    hide();
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
            showing = false;
        }
    }

    Timer {
        id: autoHideTimer
        interval: 3000
        onTriggered: hide()
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
        target: ScreenshotService
        function onScreenshotCaptured(path, image) {
            flashAnimation.start();
            screenshotPreview.show(path, image);
        }
    }
}
