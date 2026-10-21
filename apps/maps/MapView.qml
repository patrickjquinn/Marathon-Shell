import QtQuick
import QtWebChannel
import QtWebEngine
import Sailfish.Silica 1.0

// MapLibre GL JS in a WebEngineView (web/maps.html). QML drives it through
// window.MarathonMaps.* and hears back through MapsBridge.
Item {
    id: root

    signal ready
    signal clicked(real latitude, real longitude)
    signal failed(string message)
    signal lost
    signal notice(string text)

    function run(js) {
        web.runJavaScript(js);
    }

    function reload() {
        web.reload();
    }

    QtObject {
        id: bridge

        WebChannel.id: "marathonBridge"

        function notifyReady() {
            root.ready();
        }

        function onMapClicked(lat, lon) {
            root.clicked(lat, lon);
        }

        function onMapError(message) {
            root.failed(message);
        }
    }

    WebChannel {
        id: channel

        registeredObjects: [bridge]
    }

    WebEngineView {
        id: web

        anchors.fill: parent
        webChannel: channel
        // Chromium takes only an opaque or a fully transparent background;
        // the translucent overlay colour failed a CHECK on the first load.
        backgroundColor: Qt.rgba(Theme.overlayBackgroundColor.r, Theme.overlayBackgroundColor.g, Theme.overlayBackgroundColor.b, 1)
        settings.javascriptEnabled: true
        settings.localContentCanAccessFileUrls: true
        settings.localContentCanAccessRemoteUrls: true
        settings.allowRunningInsecureContent: false
        settings.errorPageEnabled: false
        settings.showScrollBars: false
        // MARATHON_APP_PATH is the runner's install root; direct QML runs use
        // the user-local dev install.
        url: {
            const root = typeof MARATHON_APP_PATH !== "undefined" && MARATHON_APP_PATH ? String(MARATHON_APP_PATH) : "";
            if (root.length > 0)
                return "file://" + root + "/web/maps.html";
            return "file://" + StandardPaths.genericData + "/marathon-apps/maps/web/maps.html";
        }
        onJavaScriptConsoleMessage: (level, message, lineNumber, source) => {
            if (level >= WebEngineView.WarningMessageLevel)
                console.warn("Maps:WebJS", source + ":" + lineNumber, message);
        }
        onCertificateError: error => {
            error.rejectCertificate();
            const host = String(error.url).replace(/^\w+:\/\/([^\/:]+).*$/, "$1");
            root.notice(qsTr("Couldn't connect securely to %1, so some map data didn't load.").arg(host));
        }
        onRenderProcessTerminated: (terminationStatus, exitCode) => {
            if (terminationStatus === WebEngineView.NormalTerminationStatus)
                return;
            console.warn("Maps: renderer terminated (" + terminationStatus + ", code " + exitCode + "), reloading");
            root.lost();
            web.reload();
        }
    }
}
