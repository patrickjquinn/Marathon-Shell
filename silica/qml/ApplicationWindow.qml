// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ApplicationWindow. API from the Silica public documentation; implementation
// clean-room. It is an Item, so it works as the root of the QQuickView that
// SailfishApp::createView() returns.
//
// On a phone, via Keel.Shell (direct mode, ADR-0016, or keel-shell,
// keel/shell/PROTOCOL.md):
//   * deviceOrientation follows Shell.orientation (degrees: 0 portrait,
//     90 landscape, 180 inverted portrait, 270 inverted landscape) and the UI
//     orientation is reported back with Shell.setContentOrientation().
//   * the cover is rendered into a second top-level window whose title is
//     "<KEEL_SHELL_COVER_TITLE>:<app name>" (default marker "keel:cover").
//     In direct mode Shell.prepareCoverWindow() tags it CATEGORY=cover
//     before it is first shown, so Lipstick takes it as the app's cover;
//     under keel-shell, keel-shell maps it to such a window. Cover.status
//     follows Shell.coverStatus.
//   * activate() calls Shell.activate().
import QtQuick
import QtQuick.Window 2.15 as QtWindow
import Keel 1.0
import Sailfish.Silica.private 1.0

Item {
    id: window

    // --- Public API ------------------------------------------------------------
    property var initialPage
    property var cover
    readonly property alias pageStack: stack
    default property alias _contentChildren: content.data
    readonly property alias contentItem: content

    property int allowedOrientations: Orientation.All
    readonly property int defaultAllowedOrientations: Orientation.Portrait | Orientation.Landscape
                                                      | Orientation.LandscapeInverted
    property int defaultPageCutoutMode: CutoutMode.AvoidLandscapeCutout
    // Allowed orientations of pages that do not set their own (older Sailfish
    // SDK app templates set this).
    property int _defaultPageOrientations: Orientation.Portrait
    // Writable so tests and apps without keel-shell can drive it.
    property int deviceOrientation: Shell.connected || Shell.direct ? _fromDegrees(Shell.orientation)
                                                                   : Orientation.Portrait
    readonly property int orientation: _effectiveOrientation
    readonly property real screenRotation: _degrees(_effectiveOrientation)
    property real bottomMargin: 0
    readonly property WindowBackground background: WindowBackground { }

    // --- What Silica's BSD QML reads from the window ---------------------------
    // (names from that QML; Keel's implementation)
    property alias __silica_applicationwindow_instance: window
    // Label's default textFormat, as in Silica (Text.AutoText). Apps that
    // show untrusted text set Text.PlainText here or on the Label.
    property int _defaultLabelFormat: Text.AutoText
    // A locked-open pulley menu dims the window content.
    property bool _dimScreen
    readonly property bool _dimmingActive: _dimScreen || dimAnimation.running
    readonly property alias _touchBlockerItem: touchBlocker
    readonly property alias _rotatingItem: rotator
    readonly property alias _contentScale: contentScale
    readonly property alias indicatorParentItem: indicatorParent
    readonly property bool _rotating: false
    readonly property bool _backgroundVisible: true
    // As in Silica: transparent unless the app sets a background colour
    // (DialogHeader fills its band with it over the wallpaper).
    readonly property color _backgroundColor: window.background.color.a > 0 ? window.background.color
                                                                           : Theme.rgba(Theme.overlayBackgroundColor, 0)
    property color dimmedRegionColor: Theme.highlightDimmerColor
    // Faded out and in by Silica's page orientation transition.
    property real _windowOpacity: 1.0

    // The orientation a page allowing `allowed` takes on a device in
    // `device` orientation (default: the current device orientation; Silica's
    // PageStack.qml calls it with `allowed` only).
    function _selectOrientation(allowed, device) {
        if (device === undefined)
            device = deviceOrientation
        if (device & allowed)
            return device
        var order = [Orientation.Portrait, Orientation.Landscape, Orientation.LandscapeInverted,
                     Orientation.PortraitInverted]
        for (var i = 0; i < order.length; ++i)
            if (order[i] & allowed)
                return order[i]
        return Orientation.Portrait
    }

    // Keel keeps these widely used Silica window properties available.
    readonly property bool applicationActive: Shell.connected || Shell.direct
                                              ? Shell.active : Qt.application.state === Qt.ApplicationActive
    property alias _coverWindow: coverWindowLoader.item
    readonly property Item _coverItem: _coverHolder.coverItem

    signal _activateRequested()

    function activate() {
        _activateRequested()
        if (Shell.connected || Shell.direct) {
            Shell.activate()
        } else if (QtWindow.Window.window) {
            QtWindow.Window.window.raise()
            QtWindow.Window.window.requestActivate()
        }
    }

    function deactivate() {
        if (QtWindow.Window.window)
            QtWindow.Window.window.showMinimized()
    }

    // Pages loaded from URLs are created here so that their context chain is
    // page file -> this file -> the file declaring the ApplicationWindow,
    // which is how Silica pages see `pageStack` and ids from main.qml.
    function _createComponent(url) {
        return Qt.createComponent(url)
    }

    // --- Orientation -----------------------------------------------------------
    function _fromDegrees(d) {
        switch (((d % 360) + 360) % 360) {
        case 90: return Orientation.Landscape
        case 180: return Orientation.PortraitInverted
        case 270: return Orientation.LandscapeInverted
        default: return Orientation.Portrait
        }
    }
    function _degrees(o) {
        switch (o) {
        case Orientation.Landscape: return 90
        case Orientation.PortraitInverted: return 180
        case Orientation.LandscapeInverted: return 270
        default: return 0
        }
    }
    // Silica's Page chooses its own orientation (allowedOrientations, the
    // device orientation, _selectOrientation()); the window follows the
    // current page.
    readonly property int _effectiveOrientation: stack.currentPage ? stack.currentPage.orientation
                                                                   : _selectOrientation(allowedOrientations, deviceOrientation)
    on_EffectiveOrientationChanged: Shell.setContentOrientation(_degrees(_effectiveOrientation))

    // --- Background --------------------------------------------------------------
    // On a phone the window is translucent and Lipstick draws the blurred
    // ambience wallpaper behind it (Keel.Shell sets BACKGROUND_VISIBLE on the
    // window, as Silica's Qt 5 window does); the window itself draws only a
    // background colour the app sets. Without a compositor that
    // does (desktop, offscreen screenshots) Keel draws what Lipstick would:
    // the ambience wallpaper (Keel's "Harbour" ambiences by default) cropped
    // to the window, blurred (image://keelambience), toned towards the
    // ambience and overlaid with the fine glass dither of Sailfish OS 4/5.
    // Tone and blur were fitted to published Sailfish screenshots
    // (keel/silica/tests/screenshots/reference/SOURCES.md).
    Rectangle {
        anchors.fill: parent
        visible: Shell.phone && window.background.color.a > 0
        color: window.background.color
    }
    Item {
        id: defaultBackground
        anchors.fill: parent
        visible: !Shell.phone
        readonly property bool light: Theme.colorScheme === Theme.DarkOnLight
        readonly property color color: window.background.color.a > 0 ? window.background.color
                                                                     : (light ? "#e9eff2" : "#060b12")
        readonly property string wallpaper: window.background.image.toString() !== ""
                                            ? window.background.image.toString()
                                            : (Theme._backgroundImage !== ""
                                               ? Theme._backgroundImage
                                               : "qrc:/qt/qml/Sailfish/Silica/ambience/harbour-"
                                                 + (light ? "light" : "dark") + ".jpg")

        Rectangle {
            anchors.fill: parent
            color: defaultBackground.color
        }
        Image {
            id: wallpaperImage
            objectName: "keelAmbienceWallpaper"
            anchors.fill: parent
            visible: window.background.color.a === 0 && status === Image.Ready
            smooth: true
            cache: true
            // A new size re-crops and re-blurs: only whole pixels count.
            source: !Shell.phone && defaultBackground.wallpaper !== "" && width > 0 && height > 0
                    ? "image://keelambience/" + encodeURIComponent(defaultBackground.wallpaper)
                      + "?w=" + Math.round(width) + "&h=" + Math.round(height)
                    : ""
        }
        // The compositor's tone: a dark ambience's wallpaper is dimmed to
        // about a third and tinted with the highlight dimmer; a light one is
        // washed towards white.
        Rectangle {
            anchors.fill: parent
            visible: wallpaperImage.visible
            color: defaultBackground.light ? "white" : "black"
            opacity: defaultBackground.light ? 0.45 : 0.62
        }
        Rectangle {
            anchors.fill: parent
            visible: wallpaperImage.visible && !defaultBackground.light
            color: Theme.highlightDimmerColor
            opacity: 0.12
        }
        Image {
            anchors.fill: parent
            visible: wallpaperImage.visible
            source: "qrc:/qt/qml/Sailfish/Silica/ambience/glass-dither.png"
            fillMode: Image.Tile
            smooth: false
            opacity: defaultBackground.light ? 0.6 : 1.0
        }
    }

    // --- Content ---------------------------------------------------------------------
    // Pages rotate themselves (Silica's BSD Page.qml); the stack and the
    // app's own children stay in screen coordinates.
    Item {
        id: clipping
        anchors {
            fill: parent
            bottomMargin: Math.max(window.bottomMargin, stack.imSize)
        }
        opacity: window._windowOpacity * dimming
        property real dimming: window._dimScreen ? Theme.opacityLow : 1.0
        Behavior on dimming { FadeAnimation { id: dimAnimation } }
        // Text selection handles zoom the content (Silica's BSD TextBase.qml).
        transform: Scale {
            id: contentScale
            property bool animationRunning: xAnim.running || yAnim.running
            Behavior on xScale { NumberAnimation { id: xAnim; duration: 100 } }
            Behavior on yScale { NumberAnimation { id: yAnim; duration: 100 } }
        }

        // The app's own children share this item with the page stack, as in
        // Silica: a child with z < 0 (a camera viewfinder) is drawn under
        // the pages, the others over them.
        Item {
            id: content
            property alias _windowOpacity: content.opacity
            anchors.fill: parent

            PageStack {
                id: stack

                // What Silica's ApplicationWindow adds to its stack.
                readonly property int currentOrientation: window._effectiveOrientation
                readonly property bool verticalOrientation: (currentOrientation & Orientation.LandscapeMask) === 0
                readonly property bool horizontalOrientation: !verticalOrientation
                readonly property real imSize: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
                readonly property real panelSize: imSize

                anchors.fill: parent
                focus: true
            }
        }

        Item {
            id: indicatorParent
            anchors.fill: parent
        }

        TouchBlocker {
            id: touchBlocker
            anchors.fill: parent
            enabled: false
        }
    }

    // Overlays that follow the page orientation (_rotatingItem).
    Item {
        id: rotator
        readonly property bool landscape: (window._effectiveOrientation & Orientation.LandscapeMask) !== 0
        anchors.centerIn: parent
        width: landscape ? window.height : window.width
        height: landscape ? window.width : window.height
        rotation: window.screenRotation
    }

    // --- Cover ---------------------------------------------------------------------
    QtObject {
        id: _coverHolder
        property Item coverItem: null
        function load() {
            if (coverItem || window.cover === undefined || window.cover === null || window.cover === "")
                return coverItem
            var c = window.cover
            var item = null
            if (c.createObject !== undefined) {
                item = c.createObject(null)
            } else if (typeof c === "object" && c.parent !== undefined) {
                item = c
            } else {
                var comp = window._createComponent(Qt.resolvedUrl(String(c), window))
                if (comp.status === Component.Ready)
                    item = comp.createObject(null)
                else
                    console.warn("ApplicationWindow: cannot load cover", c, comp.errorString())
            }
            coverItem = item
            return item
        }
    }
    function _loadCover() { return _coverHolder.load() }

    Loader {
        id: coverWindowLoader
        active: Shell.coverEnabled && window.cover !== undefined && window.cover !== null
        sourceComponent: QtWindow.Window {
            id: coverWindow
            // PROTOCOL.md section 3: the title carries the marker and is set
            // before the window is shown; the cover must not be a transient
            // of the main window. The window is shown only once it is
            // prepared: in direct mode it must carry CATEGORY=cover before
            // its first buffer reaches Lipstick.
            property bool _prepared: false
            title: Shell.coverTitle + (Qt.application.name !== "" ? ":" + Qt.application.name : "")
            transientParent: null
            width: Theme.coverSizeLarge.width
            height: Theme.coverSizeLarge.height
            color: "transparent"
            visible: _prepared
            Component.onCompleted: {
                Shell.prepareCoverWindow(coverWindow)
                var item = window._loadCover()
                if (item) {
                    item.parent = coverWindow.contentItem
                    item.anchors.fill = coverWindow.contentItem
                }
                // Lipstick draws the cover background behind a transparent
                // cover (CoverBackground), as for Silica's covers.
                Shell.setLipstickProperty(coverWindow, "TRANSPARENT", !!(item && item.transparent))
                _prepared = true
            }
        }
    }

    // Notices are shown in this window's indicator layer.
    Component.onDestruction: if (Notices._window === window) Notices._window = null
    Component.onCompleted: {
        Notices._window = window
        if (initialPage === undefined || initialPage === null || initialPage === "")
            return
        // A page given by URL is relative to the app's file that declares the
        // window (Silica's PageStack would resolve it against its own file).
        var page = initialPage
        if (typeof page !== "object" || (page.createObject === undefined && page.parent === undefined))
            page = Qt.resolvedUrl(String(page), window)
        stack.animatorPush(page)
    }

    Connections {
        target: Shell
        function onCloseRequested() { Qt.quit() }
    }
}
