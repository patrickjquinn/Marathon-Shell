import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Gallery 1.0
import Sailfish.Share 1.0
import "../GalleryModel.js" as Model

FullscreenContentPage {
    id: root

    property var store
    property var photos: []
    property alias currentIndex: slideshow.currentIndex
    property bool overlayShown: true
    readonly property var photo: photos.length > 0 ? photos[Math.max(0, currentIndex)] : null

    function deleteCurrent() {
        const id = photo.id;
        const index = currentIndex;
        store.deletePhoto(id);
        const rest = Model.withoutId(photos, id);
        if (rest.length === 0) {
            pageStack.pop();
            return;
        }
        photos = rest;
        currentIndex = Math.min(index, rest.length - 1);
    }

    // Vertical drags open the pulley, so the page goes back sideways.
    navigationStyle: PageNavigation.Horizontal
    onPhotoChanged: store.viewerPhoto = photo
    onStatusChanged: if (status === PageStatus.Active) forceActiveFocus()
    Keys.onLeftPressed: slideshow.decrementCurrentIndex()
    Keys.onRightPressed: slideshow.incrementCurrentIndex()
    Keys.onEscapePressed: pageStack.pop()
    Component.onDestruction: store.viewerPhoto = null

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: height
        interactive: !(slideshow.currentItem as ImageViewer)?.zoomed

        PullDownMenu {
            id: menu

            objectName: "menu"

            MenuItem {
                objectName: "deleteAction"
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleted"), function () { root.deleteCurrent(); })
            }
            MenuItem {
                objectName: "shareAction"
                text: qsTr("Share")
                visible: KeelShareService.available()
                onClicked: share.trigger()
            }
            MenuItem {
                objectName: "detailsAction"
                text: qsTr("Details")
                onClicked: pageStack.push(Qt.resolvedUrl("PhotoDetailsPage.qml"), { photo: root.photo })
            }
        }

        SlideshowView {
            id: slideshow

            objectName: "slideshow"
            anchors.fill: parent
            model: root.photos

            delegate: ImageViewer {
                required property var modelData

                width: slideshow.width
                height: slideshow.height
                source: modelData.path
                active: PathView.isCurrentItem
                viewMoving: slideshow.moving
                Accessible.role: Accessible.Graphic
                Accessible.name: Model.fileName(modelData)
                onClicked: root.overlayShown = !root.overlayShown
            }
        }
    }

    Rectangle {
        objectName: "overlay"
        width: parent.width
        height: counterLabel.y + counterLabel.height + Theme.paddingLarge * 2
        visible: opacity > 0
        opacity: root.overlayShown && !menu.active ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay) }
            GradientStop { position: 1; color: "transparent" }
        }

        Behavior on opacity { FadeAnimator {} }

        Label {
            id: titleLabel

            x: Theme.horizontalPageMargin
            y: Theme.paddingLarge
            width: parent.width - 2 * Theme.horizontalPageMargin
            text: root.photo && root.photo.timestamp
                  ? Format.formatDate(new Date(root.photo.timestamp), Formatter.DateLong) : Model.fileName(root.photo)
            truncationMode: TruncationMode.Fade
            color: Theme.lightPrimaryColor
        }
        Label {
            id: counterLabel

            anchors.top: titleLabel.bottom
            x: Theme.horizontalPageMargin
            text: qsTr("%1 of %2").arg(root.currentIndex + 1).arg(root.photos.length)
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.lightSecondaryColor
        }
    }

    RemorsePopup {
        id: remorse

        objectName: "remorse"
    }

    ShareAction {
        id: share

        mimeType: "image/*"
        title: qsTr("Share image")
        resources: root.photo ? [root.photo.path] : []
    }
}
