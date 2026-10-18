pragma ComponentBehavior: Bound

import QtQuick
import QtWebEngine
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

Item {
    id: root

    required property var browser
    required property WebLayer webLayer
    required property int index
    required property int tabId
    required property string url
    required property bool isCrashed
    required property string loadError
    required property string failedUrl

    readonly property bool current: index === browser.currentTabIndex
    readonly property alias view: webView

    function loadErrorMessage(loadRequest) {
        switch (loadRequest.errorDomain) {
        case WebEngineView.CertificateErrorDomain:
            return qsTr("This site's security certificate isn't valid, so the connection isn't private. Browser blocked it to protect your data.");
        case WebEngineView.DnsErrorDomain:
            return qsTr("The address couldn't be found. Check the spelling, or check that you're online.");
        case WebEngineView.ConnectionErrorDomain:
            if (loadRequest.errorCode === -106)
                return qsTr("You're offline. Connect to Wi-Fi or mobile data and try again.");
            return qsTr("The site didn't respond. It may be down, or your connection may be unstable.");
        default:
            return loadRequest.errorString || qsTr("Something went wrong while loading this page.");
        }
    }

    function capture() {
        if (webView.visible && width > 0)
            webView.grabToImage(result => root.browser.setThumbnail(root.tabId, result), Qt.size(width / 2, height / 2));
    }

    function setTab(role, value) {
        if (index >= 0 && index < browser.tabs.count && browser.tabs.get(index)[role] !== value)
            browser.tabs.setProperty(index, role, value);
    }

    visible: current

    Timer {
        id: captureTimer

        interval: 500
        onTriggered: root.capture()
    }

    WebView {
        id: webView

        anchors.fill: parent
        focus: !root.browser.editingAddress
        url: root.url
        profile: root.browser.isPrivateMode ? root.webLayer.privateProfile : root.webLayer.normalProfile
        active: root.browser.applicationActive && root.current
        crashed: root.isCrashed
        onCrashedChanged: root.setTab("isCrashed", crashed)
        onRenderProcessTerminated: function (terminationStatus, exitCode) {
            console.warn("Browser: render process terminated (" + terminationStatus + ", code " + exitCode + ")");
            if (terminationStatus !== WebEngineView.NormalTerminationStatus) {
                root.setTab("crashCount", (root.browser.tabs.get(root.index).crashCount || 0) + 1);
                root.setTab("lastCrashAt", Date.now());
                root.setTab("isCrashed", true);
                crashed = true;
            }
        }
        onNewWindowRequested: request => {
            const reqUrl = request.requestedUrl ? request.requestedUrl.toString() : "";
            root.browser.createNewTab(reqUrl || "about:blank");
        }
        onNavigationRequested: request => {
            if (!Logic.isWebUrl(request.url.toString())) {
                console.warn("Browser: blocked navigation to unsupported scheme: " + request.url);
                request.reject();
                return;
            }
            request.accept();
        }
        onCertificateError: error => {
            console.warn("Browser: TLS certificate error for " + error.url + " (" + error.type + "): " + error.description);
            error.rejectCertificate();
            // Main-frame rejections surface as a LoadFailed error page.
            if (error.isMainFrame === false && root.current)
                Notices.show(qsTr("Some content was blocked: its security certificate isn't valid"));
        }
        onFeaturePermissionRequested: (securityOrigin, feature) => {
            webView.grantFeaturePermission(securityOrigin, feature, false);
        }
        onFullScreenRequested: request => request.accept()
        onScrollPositionChanged: {
            if (root.current)
                root.webLayer.scrolled(scrollPosition.y);
        }
        onUrlChanged: {
            if (!root.browser.updatingTabUrl)
                root.setTab("url", url.toString());
        }
        onTitleChanged: {
            root.setTab("title", title);
            root.browser.retitleHistory(url.toString(), title);
        }
        onLoadingChanged: function (loadRequest) {
            const loading = loadRequest.status === WebEngineView.LoadStartedStatus;
            root.setTab("isLoading", loading);
            if (loading)
                root.setTab("loadError", "");
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                root.setTab("title", title);
                root.browser.addToHistory(url.toString(), title);
                root.setTab("isCrashed", false);
                captureTimer.restart();
            }
            // -3 is net::ERR_ABORTED: superseded by another navigation, not a failure.
            if (loadRequest.status === WebEngineView.LoadFailedStatus && loadRequest.errorCode !== -3) {
                console.warn("Browser: load failed for " + loadRequest.url + ": " + loadRequest.errorString + " (" + loadRequest.errorCode + ")");
                root.setTab("failedUrl", loadRequest.url.toString());
                root.setTab("loadError", root.loadErrorMessage(loadRequest));
            }
        }
        onCanGoBackChanged: root.setTab("canGoBack", canGoBack)
        onCanGoForwardChanged: root.setTab("canGoForward", canGoForward)
        onLoadProgressChanged: root.setTab("loadProgress", loadProgress)
    }

    Rectangle {
        anchors.fill: parent
        visible: root.loadError !== ""
        color: Theme.overlayBackgroundColor

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.horizontalPageMargin
            spacing: Theme.paddingLarge

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "image://theme/icon-l-warning"
            }
            InfoLabel {
                text: qsTr("Can't open this page")
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.loadError
                color: Theme.secondaryColor
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Elide
                elide: Text.ElideMiddle
                text: Logic.displayHost(root.failedUrl)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Try again")
                onClicked: {
                    root.setTab("loadError", "");
                    if (root.url === root.failedUrl || root.failedUrl === "")
                        webView.reload();
                    else
                        root.browser.navigateTo(root.failedUrl);
                }
            }
        }
    }
}
