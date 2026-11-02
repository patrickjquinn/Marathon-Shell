pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "GalleryModel.js" as Model
import "pages"
import "cover"

ApplicationWindow {
    id: root

    property var albums: MediaLibrary.albums
    property var photos: []
    property var videos: []
    readonly property var memories: Model.memoryClusters(photos, videos, new Date())
    readonly property bool scanning: MediaLibrary.isScanning
    // The photo open full screen, shown on the cover.
    property var viewerPhoto: null
    property string route: typeof MARATHON_APP_ROUTE !== "undefined" ? MARATHON_APP_ROUTE : ""
    property string routeParams: typeof MARATHON_APP_ROUTE_PARAMS !== "undefined" ? MARATHON_APP_ROUTE_PARAMS : ""
    // The file "/image" asked for, until the library lists it.
    property string pendingUrl: ""

    function refresh() {
        photos = MediaLibrary.getAllPhotos();
        videos = MediaLibrary.getVideos();
        showPending();
    }

    // "/image" with {path}: that photo full screen.
    function openRoute(name, paramsJson) {
        if (name !== "/image")
            return;
        let path = "";
        try {
            path = JSON.parse(paramsJson || "{}").path || "";
        } catch (e) {}
        if (path === "")
            return;
        pendingUrl = "file://" + path;
        showPending();
    }

    function showPending() {
        const stills = photos.filter(p => !Model.isVideo(p));
        const index = stills.findIndex(p => p.path === pendingUrl);
        if (index < 0)
            return;
        pendingUrl = "";
        const first = pageStack.find(p => !pageStack.previousPage(p));
        if (pageStack.currentPage !== first)
            pageStack.pop(first, PageStackAction.Immediate);
        pageStack.push(Qt.resolvedUrl("pages/PhotoViewerPage.qml"), {
            store: root,
            photos: stills,
            currentIndex: index
        }, PageStackAction.Immediate);
    }

    function deletePhoto(id) {
        MediaLibrary.deleteMedia(id);
    }

    appId: "gallery"
    cover: Component {
        GalleryCover {
            photos: root.photos
            photo: root.viewerPhoto
        }
    }
    initialPage: Component {
        GalleryPage {
            store: root
        }
    }
    Component.onCompleted: {
        MediaLibrary.scanLibraryAsync();
        openRoute(route, routeParams);
        Qt.callLater(refresh);
    }

    GalleryActions {
        store: root
    }

    Connections {
        target: typeof NavigationRouter !== "undefined" ? NavigationRouter : null
        ignoreUnknownSignals: true

        function onDeepLinkRequested(appId, route, params) {
            if (appId !== root.appId)
                return;
            root.activate();
            root.openRoute(route, JSON.stringify(params || {}));
            // Pictures' subfolders are not watched: a new screenshot needs a scan.
            if (root.pendingUrl !== "")
                MediaLibrary.scanLibraryAsync();
        }
    }

    Connections {
        target: MediaLibrary
        function onScanComplete() {
            root.refresh();
        }
        function onLibraryChanged() {
            root.refresh();
        }
    }
}
