import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Sailfish.Gallery 1.0
import Sailfish.Share 1.0
import "../components"

FullscreenContentPage {
    id: page

    property var app
    readonly property string capture: app.camera.latestCapture
    readonly property bool video: app.latestIsVideo

    function deleteCapture() {
        const indexed = (video ? MediaLibrary.getVideos() : MediaLibrary.getAllPhotos())
            .find(m => m.path === capture);
        if (indexed)
            MediaLibrary.deleteMedia(indexed.id);
        app.camera.deleteLatestCapture();
        pageStack.pop();
    }

    // Vertical drags open the pulley, so the page goes back sideways.
    navigationStyle: PageNavigation.Horizontal
    palette.colorScheme: Theme.LightOnDark

    Rectangle {
        anchors.fill: parent
        color: Theme.darkPrimaryColor
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: height
        interactive: !(viewer.item as ImageViewer)?.zoomed

        PullDownMenu {
            MenuItem {
                objectName: "deleteAction"
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleted"), function () { page.deleteCapture(); })
            }
            MenuItem {
                objectName: "shareAction"
                text: qsTr("Share")
                visible: KeelShareService.available()
                onClicked: share.trigger()
            }
            MenuItem {
                objectName: "galleryAction"
                text: qsTr("Open in Gallery")
                onClicked: Navigation.launchApp("gallery")
            }
        }

        Loader {
            id: viewer

            objectName: "viewer"
            anchors.fill: parent
            sourceComponent: page.video ? videoComponent : photoComponent
        }
    }

    Component {
        id: photoComponent

        ImageViewer {
            objectName: "photoViewer"
            source: page.capture
            Accessible.role: Accessible.Graphic
            Accessible.name: qsTr("Last photo")
        }
    }

    Component {
        id: videoComponent

        VideoPlayback {
            objectName: "videoPlayback"
            source: page.capture
        }
    }

    RemorsePopup {
        id: remorse

        objectName: "remorse"
    }

    ShareAction {
        id: share

        mimeType: page.video ? "video/mp4" : "image/jpeg"
        title: page.video ? qsTr("Share video") : qsTr("Share photo")
        resources: page.capture !== "" ? [page.capture] : []
    }
}
