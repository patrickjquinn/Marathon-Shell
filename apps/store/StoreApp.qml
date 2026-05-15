import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MApp {
    id: root

    appId: "store"
    appName: "App Store"
    appIcon: "assets/icon.svg"

    readonly property string flathubApi: "https://flathub.org/api/v2"
    readonly property string stateDir: "/run/user/" + (typeof userUid !== "undefined" ? userUid : "1000") + "/marathon-store-state"

    // Density factor for sizing literals. Marathon's shell chrome uses
    // Constants.scaleFactor everywhere (≈ 2.0 on a phone-class DPI), so
    // raw pixel dimensions on cards/heroes would visually mismatch the
    // top/bottom bars. Every fixed dimension below multiplies by `sf`.
    readonly property real sf: Constants.scaleFactor || 1.0

    property var collections: ({})
    property var appOfTheDay: null
    property var appstreamCache: ({})
    property var installedApps: []
    property var pendingUpdates: []
    property var installState: ({})
    property bool catalogLoading: false
    property string lastError: ""
    property int activeTab: 0

    // Rail ordering matters: railApps() walks this list and removes apps
    // already shown in an earlier rail, so popular apps don't appear three
    // times across the page.
    readonly property var railOrder: ["mobile", "trending", "popular", "recently-added", "verified"]

    signal openDetailRequested(string appId, var summary)

    function todayUtc() {
        const d = new Date();
        const m = (d.getUTCMonth() + 1).toString().padStart(2, "0");
        const day = d.getUTCDate().toString().padStart(2, "0");
        return d.getUTCFullYear() + "-" + m + "-" + day;
    }

    function pickAarch64(hits) {
        const out = [];
        for (let i = 0; i < hits.length; i++) {
            const a = hits[i];
            if (a.arches && a.arches.indexOf("aarch64") >= 0)
                out.push(a);
        }
        return out;
    }

    // SSRF defence: pin every outbound HTTP to flathub.org. A poisoned remote
    // response that redirected us at a LAN host, or a crafted collection name
    // with a different scheme, gets refused.
    function isFlathubUrl(u) {
        return typeof u === "string" && u.indexOf("https://flathub.org/") === 0;
    }

    function fetchJson(url, body, cb) {
        if (!root.isFlathubUrl(url)) {
            cb(null, "refusing non-flathub url");
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.open(body ? "POST" : "GET", url);
        xhr.setRequestHeader("Accept", "application/json");
        if (body)
            xhr.setRequestHeader("Content-Type", "application/json");
        const timer = Qt.createQmlObject('import QtQuick; Timer { interval: 15000; repeat: false }', root);
        timer.triggered.connect(function () {
            xhr.abort();
            cb(null, "timeout");
        });
        timer.start();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            timer.stop();
            if (xhr.status !== 200) {
                cb(null, "HTTP " + xhr.status);
                return;
            }
            if (xhr.responseText.length > 1024 * 1024) {
                cb(null, "response too large");
                return;
            }
            try {
                cb(JSON.parse(xhr.responseText), null);
            } catch (e) {
                cb(null, "parse: " + e);
            }
        };
        if (body)
            xhr.send(JSON.stringify(body));
        else
            xhr.send();
    }

    // Icon / screenshot URLs are bound to Image.source. Clamp to the Flathub
    // CDN so a poisoned response can't make us load file:// or intranet HTTP.
    function safeImageUrl(u) {
        if (typeof u !== "string")
            return "";
        if (u.indexOf("https://dl.flathub.org/") === 0)
            return u;
        if (u.indexOf("https://flathub.org/") === 0)
            return u;
        return "";
    }

    function readLocalJson(path, cb) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + path);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.responseText.length === 0) {
                cb(null);
                return;
            }
            try {
                cb(JSON.parse(xhr.responseText));
            } catch (e) {
                cb(null);
            }
        };
        xhr.send(null);
    }

    function loadCollection(name) {
        catalogLoading = true;
        fetchJson(flathubApi + "/collection/" + name + "?page=1&per_page=24&locale=en", null, function (data, err) {
            catalogLoading = false;
            if (err) {
                lastError = name + ": " + err;
                return;
            }
            const next = Object.assign({}, root.collections);
            next[name] = pickAarch64(data.hits || []);
            root.collections = next;
        });
    }

    function railApps(name) {
        const all = root.collections[name] || [];
        if (all.length === 0)
            return [];
        const seen = {};
        if (root.appOfTheDay && root.appOfTheDay.id)
            seen[root.appOfTheDay.id] = true;
        for (let i = 0; i < root.railOrder.length; i++) {
            const r = root.railOrder[i];
            if (r === name)
                break;
            const list = root.collections[r] || [];
            for (let j = 0; j < list.length; j++) {
                const id = list[j].app_id || list[j].id;
                if (id)
                    seen[id] = true;
            }
        }
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const id = all[i].app_id || all[i].id;
            if (!id || !seen[id])
                out.push(all[i]);
        }
        return out;
    }

    function loadAppOfTheDay() {
        fetchJson(flathubApi + "/app-picks/app-of-the-day/" + todayUtc(), null, function (data, err) {
            if (err || !data || !data.app_id)
                return;
            fetchJson(flathubApi + "/appstream/" + data.app_id, null, function (full, ferr) {
                if (ferr || !full)
                    return;
                root.appOfTheDay = full;
            });
        });
    }

    function loadAppstream(appId, cb) {
        if (root.appstreamCache[appId]) {
            cb(root.appstreamCache[appId]);
            return;
        }
        fetchJson(flathubApi + "/appstream/" + appId, null, function (full, err) {
            if (err || !full) {
                cb(null);
                return;
            }
            const next = Object.assign({}, root.appstreamCache);
            next[appId] = full;
            root.appstreamCache = next;
            cb(full);
        });
    }

    function loadInstalled() {
        readLocalJson(stateDir + "/installed.json", function (data) {
            root.installedApps = data && data.installed ? data.installed : [];
        });
    }

    function loadUpdates() {
        readLocalJson(stateDir + "/updates.json", function (data) {
            root.pendingUpdates = data && data.updates ? data.updates : [];
        });
    }

    function refreshState() {
        Qt.openUrlExternally("marathon-store://refresh-state/all");
        stateRefreshTimer.restart();
    }

    function pollInstallState() {
        const watched = Object.keys(root.installState);
        for (let i = 0; i < watched.length; i++) {
            const appId = watched[i];
            const path = stateDir + "/install-progress-" + appId + ".json";
            readLocalJson(path, function (data) {
                if (!data || !data.appId)
                    return;
                const next = Object.assign({}, root.installState);
                next[data.appId] = data;
                root.installState = next;
                if (data.state === "done" || data.state === "failed" || data.state === "cancelled") {
                    root.loadInstalled();
                    root.loadUpdates();
                }
            });
        }
    }

    function brandingColor(app) {
        if (!app || !app.branding)
            return MColors.surface;
        const list = app.branding;
        for (let i = 0; i < list.length; i++) {
            if (list[i].scheme_preference === "dark" && list[i].type === "primary")
                return list[i].value;
        }
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === "primary")
                return list[i].value;
        }
        return MColors.surface;
    }

    function bestScreenshotSrc(sizes) {
        if (!sizes || sizes.length === 0)
            return "";
        let best = sizes[0];
        for (let i = 0; i < sizes.length; i++) {
            const w = parseInt(sizes[i].width || "0", 10);
            if (w > 400 && w <= 1280)
                best = sizes[i];
        }
        return best.src || "";
    }

    function isInstalled(appId) {
        for (let i = 0; i < installedApps.length; i++) {
            if (installedApps[i].app_id === appId)
                return true;
        }
        return false;
    }

    function hasUpdate(appId) {
        for (let i = 0; i < pendingUpdates.length; i++) {
            if (pendingUpdates[i].app_id === appId)
                return true;
        }
        return false;
    }

    function isValidRef(appId) {
        if (typeof appId !== "string" || appId.indexOf("..") >= 0)
            return false;
        return /^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$/.test(appId);
    }

    function trackInstall(appId) {
        const next = Object.assign({}, root.installState);
        next[appId] = {
            appId: appId,
            state: "pending",
            percent: -1,
            ts: Date.now() / 1000
        };
        root.installState = next;
        installPollTimer.running = true;
    }

    function installApp(appId) {
        if (!isValidRef(appId)) {
            root.lastError = "Refusing to install invalid ref: " + appId;
            return;
        }
        root.trackInstall(appId);
        Qt.openUrlExternally("marathon-store://install/" + appId);
    }

    function uninstallApp(appId) {
        if (!isValidRef(appId))
            return;
        root.trackInstall(appId);
        Qt.openUrlExternally("marathon-store://uninstall/" + appId);
    }

    function updateAll() {
        Qt.openUrlExternally("marathon-store://update-all/x");
        stateRefreshTimer.restart();
    }

    function openDetail(appOrId) {
        const id = typeof appOrId === "string" ? appOrId : (appOrId.app_id || appOrId.id);
        if (!id || !isValidRef(id))
            return;
        root.openDetailRequested(id, typeof appOrId === "object" ? appOrId : null);
    }

    Timer {
        id: stateRefreshTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.loadInstalled();
            root.loadUpdates();
        }
    }

    Timer {
        id: installPollTimer
        interval: 700
        repeat: true
        triggeredOnStart: true
        running: false
        onTriggered: {
            root.pollInstallState();
            let anyInFlight = false;
            const ids = Object.keys(root.installState);
            for (let i = 0; i < ids.length; i++) {
                const s = root.installState[ids[i]];
                if (s && s.state !== "done" && s.state !== "failed" && s.state !== "cancelled") {
                    anyInFlight = true;
                    break;
                }
            }
            if (!anyInFlight)
                running = false;
        }
    }

    // Stagger startup XHRs so we don't slam Flathub with 6 parallel requests
    // and trip their rate-limit on first paint.
    Timer {
        id: startupTimer
        interval: 150
        repeat: true
        property var queue: []
        onTriggered: {
            if (queue.length === 0) {
                running = false;
                return;
            }
            const next = queue.shift();
            next();
        }
    }

    Component.onCompleted: {
        startupTimer.queue = [function () {
                root.loadAppOfTheDay();
            }, function () {
                root.loadCollection("mobile");
            }, function () {
                root.loadCollection("trending");
            }, function () {
                root.loadCollection("popular");
            }, function () {
                root.loadCollection("recently-added");
            }, function () {
                root.loadCollection("verified");
            }, function () {
                root.refreshState();
            }];
        startupTimer.running = true;
    }

    // --------------------------------------------------------------------
    // Presentation: StackView for push/pop nav to detail page; the initial
    // item hosts a StackLayout that swaps Discover/Installed/Updates pages
    // driven by an MTabBar (Clock-app pattern). This matches the rest of
    // Marathon (Clock, Browser drawer) and gives us the system tab styling,
    // gradient indicator, haptics, and a11y for free.
    // --------------------------------------------------------------------

    content: Rectangle {
        id: contentRoot
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navStack
            anchors.fill: parent
            initialItem: homeShell

            pushEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: navStack.width
                    to: 0
                    duration: MMotion.moderate
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.7
                    to: 1.0
                    duration: MMotion.quick
                }
            }
            pushExit: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.6
                    duration: MMotion.quick
                }
            }
            popEnter: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0.6
                    to: 1.0
                    duration: MMotion.quick
                }
            }
            popExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: navStack.width
                    duration: MMotion.moderate
                    easing.type: MMotion.easingStandard
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.7
                    duration: MMotion.quick
                }
            }
        }

        Connections {
            target: root
            function onBackPressed() {
                if (navStack.depth > 1)
                    navStack.pop();
            }
            function onOpenDetailRequested(appId, summary) {
                navStack.push(detailPage, {
                    "appId": appId,
                    "summaryApp": summary
                });
            }
        }
    }

    // --------------------------------------------------------------------
    // Home shell: top bar, tabbed body, bottom MTabBar.
    // --------------------------------------------------------------------
    Component {
        id: homeShell

        Item {
            id: shellRoot
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                MTopBar {
                    id: titleBar
                    Layout.fillWidth: true
                    title: ["Discover", "Installed", "Updates"][root.activeTab]
                    actions: [
                        MIconButton {
                            iconName: "refresh-cw"
                            iconSize: 18
                            a11yName: "Refresh catalog"
                            onClicked: {
                                MHaptics.lightImpact();
                                root.refreshState();
                                if (root.activeTab === 0) {
                                    root.loadCollection("mobile");
                                    root.loadCollection("trending");
                                    root.loadCollection("popular");
                                    root.loadCollection("recently-added");
                                    root.loadCollection("verified");
                                    root.loadAppOfTheDay();
                                }
                            }
                        }
                    ]
                }

                StackLayout {
                    id: tabStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.activeTab

                    Loader {
                        sourceComponent: discoverPage
                        active: true
                    }
                    Loader {
                        sourceComponent: installedPage
                        active: root.activeTab === 1 || installedApps.length > 0
                    }
                    Loader {
                        sourceComponent: updatesPage
                        active: root.activeTab === 2 || pendingUpdates.length > 0
                    }
                }

                MTabBar {
                    id: bottomTabs
                    Layout.fillWidth: true
                    activeTab: root.activeTab
                    tabs: [
                        {
                            "label": "Discover",
                            "icon": "compass"
                        },
                        {
                            "label": "Installed",
                            "icon": "package"
                        },
                        {
                            "label": "Updates",
                            "icon": "cloud-download"
                        }
                    ]
                    // refreshState() triggers the refresh-state script which
                    // rewrites installed.json + updates.json. The 1.5s
                    // stateRefreshTimer then reloads from disk. This kills
                    // the race where the tab loads before flatpak has been
                    // re-listed.
                    onTabSelected: index => {
                        MHaptics.lightImpact();
                        root.activeTab = index;
                        if (index === 1 || index === 2) {
                            root.refreshState();
                            root.loadInstalled();
                            root.loadUpdates();
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------------
    // Discover page: search bar + AOTD hero + 5 rails.
    // --------------------------------------------------------------------
    Component {
        id: discoverPage

        Flickable {
            id: discoverFlick
            contentWidth: width
            contentHeight: discoverColumn.implicitHeight + MSpacing.xl
            clip: true
            flickDeceleration: MMotion.touchFlickDeceleration
            maximumFlickVelocity: MMotion.touchFlickVelocity

            ColumnLayout {
                id: discoverColumn
                width: discoverFlick.width
                spacing: MSpacing.md

                // Search row — same pattern Maps/Messages use: an Icon + the
                // canonical MTextInput component side-by-side inside a
                // surface-coloured strip. No bespoke pill rounding; the input
                // brings its own MRadius.md and focus border.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: MSpacing.sm
                    Layout.preferredHeight: Constants.touchTargetMinimum + MSpacing.sm
                    color: "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: MSpacing.md
                        anchors.rightMargin: MSpacing.md
                        anchors.topMargin: MSpacing.xs
                        anchors.bottomMargin: MSpacing.xs
                        spacing: MSpacing.sm

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            size: Constants.iconSizeSmall
                            color: MColors.textSecondary
                        }
                        MTextInput {
                            id: discoverSearch
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - parent.spacing * 2 - Constants.iconSizeSmall - (clearBtn.visible ? clearBtn.width + parent.spacing : 0)
                            placeholderText: "Search Flathub"
                            a11yName: "Search Flathub catalog"
                            onAccepted: if (text.length > 0)
                                navStack.push(searchPage, {
                                    "initialQuery": text
                                })
                        }
                        MIconButton {
                            id: clearBtn
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "x"
                            iconSize: Constants.iconSizeSmall
                            variant: "secondary"
                            a11yName: "Clear search"
                            visible: discoverSearch.text.length > 0
                            onClicked: discoverSearch.text = ""
                        }
                    }
                }

                // App of the Day hero card.
                Loader {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    active: root.appOfTheDay !== null
                    sourceComponent: appOfTheDayCard
                }

                // Rails — Repeater so the bindings re-evaluate when new
                // collections finish loading and the de-dup set changes.
                Repeater {
                    model: [
                        {
                            name: "mobile",
                            title: "On the Go",
                            subtitle: "Apps that work great on a phone"
                        },
                        {
                            name: "trending",
                            title: "Trending",
                            subtitle: "Catching on this week"
                        },
                        {
                            name: "popular",
                            title: "Popular",
                            subtitle: "What everyone’s installing"
                        },
                        {
                            name: "recently-added",
                            title: "New on Flathub",
                            subtitle: "Fresh arrivals"
                        },
                        {
                            name: "verified",
                            title: "Verified Developers",
                            subtitle: "Confirmed by the people who made them"
                        }
                    ]
                    delegate: Loader {
                        property var railApps: root.railApps(modelData.name)
                        Layout.fillWidth: true
                        active: railApps.length > 0
                        sourceComponent: railSection
                        onLoaded: {
                            item.title = modelData.title;
                            item.subtitle = modelData.subtitle;
                            item.apps = railApps;
                        }
                        onRailAppsChanged: if (item)
                            item.apps = railApps
                    }
                }

                // Skeleton placeholders while collections are loading.
                MActivityIndicator {
                    visible: root.catalogLoading && Object.keys(root.collections).length === 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: MSpacing.lg
                }
            }
        }
    }

    // --------------------------------------------------------------------
    // App of the Day hero card.
    // --------------------------------------------------------------------
    Component {
        id: appOfTheDayCard

        // AOTD wants full-bleed imagery and a gradient — MCard's built-in
        // inset content padding gets in the way, so we use a plain Rectangle
        // here and replicate the lift/press behaviour ourselves. Radius is
        // the system "small" token (4px); the rest of Marathon (Calculator,
        // Calendar cards, lists) uses Sharp/Small, not iOS-style 16-22px.
        Rectangle {
            id: aotd
            implicitHeight: Math.round(200 * root.sf)
            radius: Constants.borderRadiusSmall
            color: root.brandingColor(root.appOfTheDay)
            clip: true
            scale: aotdMouse.pressed ? 0.98 : 1.0
            Behavior on scale {
                NumberAnimation {
                    duration: MMotion.fast
                    easing.type: Easing.OutQuad
                }
            }

            Image {
                anchors.fill: parent
                source: root.appOfTheDay && root.appOfTheDay.screenshots && root.appOfTheDay.screenshots.length > 0 ? root.bestScreenshotSrc(root.appOfTheDay.screenshots[0].sizes) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                opacity: 0.4
            }
            Rectangle {
                anchors.fill: parent
                radius: aotd.radius
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(0, 0, 0, 0.10)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.rgba(0, 0, 0, 0.40)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(0, 0, 0, 0.70)
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: MSpacing.lg
                spacing: MSpacing.xs

                MLabel {
                    text: "APP OF THE DAY"
                    font.pixelSize: MTypography.sizeXSmall
                    font.weight: MTypography.weightBold
                    font.letterSpacing: 1.4
                    color: Qt.rgba(1, 1, 1, 0.85)
                }
                Item {
                    Layout.fillHeight: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MSpacing.md

                    Rectangle {
                        Layout.preferredWidth: Math.round(64 * root.sf)
                        Layout.preferredHeight: Math.round(64 * root.sf)
                        radius: Constants.borderRadiusSmall
                        color: Qt.rgba(1, 1, 1, 0.16)
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                        border.width: 1
                        Image {
                            anchors.fill: parent
                            anchors.margins: 8
                            source: root.appOfTheDay && root.appOfTheDay.icon ? root.appOfTheDay.icon : ""
                            sourceSize: Qt.size(128, 128)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        MLabel {
                            text: root.appOfTheDay ? root.appOfTheDay.name : ""
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: MTypography.weightBold
                            color: "white"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        MLabel {
                            text: root.appOfTheDay ? (root.appOfTheDay.summary || "") : ""
                            font.pixelSize: MTypography.sizeXSmall
                            color: Qt.rgba(1, 1, 1, 0.85)
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    MButton {
                        text: root.appOfTheDay && root.isInstalled(root.appOfTheDay.id) ? "Open" : "Install"
                        variant: "primary"
                        onClicked: {
                            if (!root.appOfTheDay)
                                return;
                            const id = root.appOfTheDay.id || root.appOfTheDay.app_id;
                            if (root.isInstalled(id))
                                Qt.openUrlExternally("marathon-store://open/" + id);
                            else
                                root.installApp(id);
                        }
                    }
                }
            }

            MouseArea {
                id: aotdMouse
                anchors.fill: parent
                z: -1
                onClicked: if (root.appOfTheDay) {
                    MHaptics.lightImpact();
                    root.openDetail(root.appOfTheDay);
                }
            }
        }
    }

    // --------------------------------------------------------------------
    // Rail section: header + horizontal scrolling MCards.
    // --------------------------------------------------------------------
    Component {
        id: railSection

        Item {
            id: section
            property string title: ""
            property string subtitle: ""
            property var apps: []
            implicitHeight: header.implicitHeight + MSpacing.sm + railList.height

            ColumnLayout {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: 0
                MLabel {
                    text: section.title
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightDemiBold
                    Layout.fillWidth: true
                }
                MLabel {
                    text: section.subtitle
                    font.pixelSize: MTypography.sizeXSmall
                    variant: "secondary"
                    Layout.fillWidth: true
                }
            }

            ListView {
                id: railList
                anchors.top: header.bottom
                anchors.topMargin: MSpacing.sm
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(176 * root.sf)
                orientation: ListView.Horizontal
                spacing: MSpacing.sm
                clip: true
                cacheBuffer: width * 2
                model: section.apps
                leftMargin: MSpacing.md
                rightMargin: MSpacing.md
                snapMode: ListView.SnapToItem
                flickDeceleration: MMotion.touchFlickDeceleration
                maximumFlickVelocity: MMotion.touchFlickVelocity
                delegate: railCard
            }
        }
    }

    // Rail card delegate. MCard wraps content in a fixed inset, which is
    // too tight for a compact rail card — we use a styled Rectangle here so
    // we control the padding precisely. Press scaling matches MCard's feel.
    Component {
        id: railCard

        Rectangle {
            id: card
            width: Math.round(200 * root.sf)
            height: Math.round(158 * root.sf)
            radius: MRadius.md
            color: MColors.surface
            border.color: MColors.border
            border.width: 1
            scale: cardMouse.pressed ? 0.96 : 1.0
            Behavior on scale {
                SpringAnimation {
                    spring: MMotion.springMedium
                    damping: MMotion.dampingMedium
                    epsilon: MMotion.epsilon
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: MSpacing.sm
                spacing: MSpacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: MSpacing.sm
                    Rectangle {
                        Layout.preferredWidth: Math.round(48 * root.sf)
                        Layout.preferredHeight: Math.round(48 * root.sf)
                        radius: Constants.borderRadiusSmall
                        color: MColors.background
                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            source: modelData.icon || ""
                            sourceSize: Qt.size(96, 96)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        MLabel {
                            text: modelData.name || modelData.app_id
                            font.pixelSize: MTypography.sizeSmall
                            font.weight: MTypography.weightDemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        MLabel {
                            text: modelData.developer_name || ""
                            variant: "tertiary"
                            font.pixelSize: MTypography.sizeXSmall
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                MLabel {
                    text: modelData.summary || ""
                    variant: "secondary"
                    font.pixelSize: MTypography.sizeXSmall
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                // Footer row: Verified chip on the left, install count or
                // state text on the right. The primary install action is on
                // the detail page — keeping the card itself clean keeps the
                // rail scannable. (Putting a touch-target-sized MButton in
                // every card crowds the layout and competes with the AOTD's
                // own CTA visually.)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MSpacing.xs
                    Rectangle {
                        visible: modelData.verification_verified === true
                        Layout.preferredHeight: Math.round(20 * root.sf)
                        Layout.preferredWidth: vChipText.implicitWidth + MSpacing.sm * 2
                        radius: Constants.borderRadiusSmall
                        color: MColors.marathonTealBright
                        MLabel {
                            id: vChipText
                            anchors.centerIn: parent
                            text: "Verified"
                            color: MColors.bb10Black
                            font.pixelSize: MTypography.sizeXSmall
                            font.weight: MTypography.weightBold
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    MLabel {
                        text: {
                            if (root.hasUpdate(modelData.app_id))
                                return "Update available";
                            if (root.isInstalled(modelData.app_id))
                                return "Installed";
                            const installs = typeof modelData.installs_last_month === "number" ? modelData.installs_last_month : 0;
                            return installs > 0 ? installs.toLocaleString() + "/mo" : "";
                        }
                        color: root.hasUpdate(modelData.app_id) ? MColors.marathonTealBright : (root.isInstalled(modelData.app_id) ? MColors.textSecondary : MColors.textTertiary)
                        font.pixelSize: MTypography.sizeXSmall
                        font.weight: root.hasUpdate(modelData.app_id) ? MTypography.weightDemiBold : MTypography.weightNormal
                    }
                }
            }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                z: -1
                onClicked: {
                    MHaptics.lightImpact();
                    root.openDetail(modelData);
                }
            }
        }
    }

    // --------------------------------------------------------------------
    // Installed page: list of installed apps using MSettingsListItem.
    // --------------------------------------------------------------------
    Component {
        id: installedPage

        Rectangle {
            color: MColors.background
            Component.onCompleted: root.loadInstalled()

            ListView {
                id: installedList
                anchors.fill: parent
                anchors.topMargin: MSpacing.sm
                clip: true
                visible: root.installedApps.length > 0
                model: root.installedApps
                spacing: 0
                delegate: MSettingsListItem {
                    title: modelData.name || modelData.app_id
                    subtitle: modelData.version ? ("v" + modelData.version) : modelData.app_id
                    iconName: "package"
                    showChevron: true
                    // Pass the full row so detail page shows the name
                    // immediately while the full appstream payload loads.
                    onSettingClicked: root.openDetail(modelData)
                }
            }

            MEmptyState {
                visible: root.installedApps.length === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "package"
                title: "Nothing installed yet"
                message: "Tap Discover to find your first app."
            }
        }
    }

    // --------------------------------------------------------------------
    // Updates page: pending updates + Update All action.
    // --------------------------------------------------------------------
    Component {
        id: updatesPage

        Rectangle {
            color: MColors.background
            Component.onCompleted: {
                root.loadUpdates();
                root.loadInstalled();
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: root.pendingUpdates.length > 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: MSpacing.md
                    Layout.preferredHeight: Math.round(88 * root.sf)
                    radius: Constants.borderRadiusSmall
                    color: MColors.bb10Elevated
                    border.color: MColors.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: MSpacing.md
                        anchors.rightMargin: MSpacing.md
                        spacing: MSpacing.md
                        Icon {
                            name: "cloud-download"
                            size: Constants.iconSizeMedium
                            color: MColors.marathonTealBright
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            MLabel {
                                text: root.pendingUpdates.length + " update" + (root.pendingUpdates.length === 1 ? "" : "s") + " available"
                                font.weight: MTypography.weightDemiBold
                            }
                            MLabel {
                                text: "Tap to update everything"
                                variant: "secondary"
                                font.pixelSize: MTypography.sizeXSmall
                            }
                        }
                        MButton {
                            text: "Update all"
                            variant: "primary"
                            onClicked: {
                                MHaptics.mediumImpact();
                                root.updateAll();
                            }
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.pendingUpdates
                    delegate: MSettingsListItem {
                        title: modelData.app_id
                        subtitle: "Update available"
                        iconName: "arrow-up"
                        showChevron: true
                        onSettingClicked: root.openDetail(modelData.app_id)
                    }
                }
            }

            MEmptyState {
                visible: root.pendingUpdates.length === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "circle-check"
                title: "Everything's up to date"
                message: "We check again every 12 hours. Tap refresh in the title bar to check now."
            }
        }
    }

    // --------------------------------------------------------------------
    // Detail page — MPage with showBackButton, scrollable body, sticky
    // bottom bar housing the primary action (Install/Open/Update).
    // --------------------------------------------------------------------
    Component {
        id: detailPage

        MPage {
            id: detailRoot
            property string appId: ""
            property var summaryApp: null
            property var fullApp: null
            readonly property var displayApp: fullApp || summaryApp
            readonly property var progress: root.installState[appId] || null

            readonly property var latestRelease: {
                const r = detailRoot.fullApp && detailRoot.fullApp.releases;
                return (r && r.length > 0) ? r[0] : null;
            }

            // Compatibility chips derived from AppStream <supports>/<requires>.
            // Flathub serialises these as `metadata.supports`, `metadata.requires`,
            // and `metadata.recommends` arrays of {type, value} pairs. We map
            // them to a small set of icons users actually understand.
            readonly property var compatItems: {
                const a = detailRoot.fullApp;
                if (!a || !a.metadata)
                    return [];
                const supports = (a.metadata.supports || []).concat(a.metadata.recommends || []);
                const items = [];
                let sawTouch = false;
                let sawPointing = false;
                let sawKeyboard = false;
                for (let i = 0; i < supports.length; i++) {
                    const s = supports[i];
                    if (!s || s.type !== "control")
                        continue;
                    if (s.value === "touch")
                        sawTouch = true;
                    if (s.value === "pointing")
                        sawPointing = true;
                    if (s.value === "keyboard")
                        sawKeyboard = true;
                }
                if (sawTouch || sawPointing || sawKeyboard) {
                    items.push({
                        icon: "smartphone",
                        label: sawTouch ? "Touch" : "No touch",
                        ok: sawTouch
                    });
                    if (sawKeyboard)
                        items.push({
                            icon: "keyboard",
                            label: "Keyboard",
                            ok: true
                        });
                }
                return items;
            }

            // Project link rows pulled from AppStream <url type="...">.
            // We omit any URL the upstream payload didn't provide.
            readonly property var linkRows: {
                const u = detailRoot.fullApp && detailRoot.fullApp.urls;
                if (!u)
                    return [];
                const out = [];
                if (u.homepage)
                    out.push({
                        label: "Website",
                        url: u.homepage,
                        ic: "external-link"
                    });
                if (u.bugtracker)
                    out.push({
                        label: "Report a bug",
                        url: u.bugtracker,
                        ic: "circle-alert"
                    });
                if (u.donation)
                    out.push({
                        label: "Donate",
                        url: u.donation,
                        ic: "heart"
                    });
                if (u.help)
                    out.push({
                        label: "Help",
                        url: u.help,
                        ic: "circle-question-mark"
                    });
                if (u.translate)
                    out.push({
                        label: "Translate",
                        url: u.translate,
                        ic: "globe"
                    });
                return out;
            }

            // Information rows — Flatpak ref, runtime, license, sizes,
            // install count. Each entry only present when the upstream
            // payload provided real data; missing fields don't take a row.
            readonly property var infoRows: {
                const app = detailRoot.displayApp;
                if (!app)
                    return [];
                const rows = [];
                if (detailRoot.fullApp && detailRoot.fullApp.bundle && detailRoot.fullApp.bundle.value)
                    rows.push({
                        k: "Flatpak ref",
                        v: detailRoot.fullApp.bundle.value,
                        ic: "package"
                    });
                if (detailRoot.fullApp && detailRoot.fullApp.metadata && detailRoot.fullApp.metadata.runtime)
                    rows.push({
                        k: "Runtime",
                        v: detailRoot.fullApp.metadata.runtime,
                        ic: "layers"
                    });
                if (app.project_license)
                    rows.push({
                        k: "License",
                        v: app.project_license,
                        ic: "file-text"
                    });
                const dl = detailRoot.fmtBytes(app.download_size);
                if (dl)
                    rows.push({
                        k: "Download size",
                        v: dl,
                        ic: "download"
                    });
                const sz = detailRoot.fmtBytes(app.installed_size);
                if (sz)
                    rows.push({
                        k: "Installed size",
                        v: sz,
                        ic: "hard-drive"
                    });
                if (app.installs_last_month && app.installs_last_month > 0)
                    rows.push({
                        k: "Monthly installs",
                        v: app.installs_last_month.toLocaleString(),
                        ic: "trending-up"
                    });
                return rows;
            }

            // Flatpak app permissions parsed from `metadata.permissions` or
            // the `[Context]` section serialised by Flathub. We surface the
            // common ones users actually care about; everything else falls
            // under "Other system access".
            readonly property var permissionItems: {
                const a = detailRoot.fullApp;
                if (!a || !a.metadata)
                    return [];
                const ctx = a.metadata.permissions || a.metadata.context || {};
                const out = [];
                const shares = (ctx.shared || []);
                if (shares.indexOf("network") >= 0)
                    out.push({
                        icon: "wifi",
                        label: "Network access",
                        detail: "Sends and receives data online"
                    });
                if (shares.indexOf("ipc") >= 0)
                    out.push({
                        icon: "share-2",
                        label: "Inter-process communication",
                        detail: "Talks to other apps on the device"
                    });
                const sockets = (ctx.sockets || []);
                if (sockets.indexOf("pulseaudio") >= 0)
                    out.push({
                        icon: "volume-2",
                        label: "Audio",
                        detail: "Play sound and record from microphones"
                    });
                if (sockets.indexOf("wayland") >= 0 || sockets.indexOf("fallback-x11") >= 0)
                    out.push({
                        icon: "monitor",
                        label: "Display",
                        detail: "Draws windows on screen"
                    });
                if (sockets.indexOf("system-bus") >= 0)
                    out.push({
                        icon: "settings",
                        label: "System services",
                        detail: "Interacts with system-wide services"
                    });
                const filesystems = (ctx.filesystems || []);
                for (let i = 0; i < filesystems.length; i++) {
                    const f = filesystems[i];
                    if (f === "host")
                        out.push({
                            icon: "folder",
                            label: "All files",
                            detail: "Full read/write access to your home folder"
                        });
                    else if (f === "home")
                        out.push({
                            icon: "folder",
                            label: "Home folder",
                            detail: "Read/write files in your home"
                        });
                    else if (f.indexOf("xdg-") === 0)
                        out.push({
                            icon: "folder",
                            label: "User folder: " + f.replace("xdg-", ""),
                            detail: "Access to a specific user folder"
                        });
                }
                const devices = (ctx.devices || []);
                if (devices.indexOf("all") >= 0)
                    out.push({
                        icon: "cpu",
                        label: "All devices",
                        detail: "Hardware access including cameras and sensors"
                    });
                else if (devices.indexOf("dri") >= 0)
                    out.push({
                        icon: "cpu",
                        label: "Graphics acceleration",
                        detail: "Uses the GPU for rendering"
                    });
                return out;
            }

            function fmtBytes(n) {
                if (!n || n <= 0)
                    return "";
                const mb = n / (1024 * 1024);
                if (mb >= 1024)
                    return (mb / 1024).toFixed(1) + " GB";
                return Math.max(1, Math.round(mb)) + " MB";
            }

            title: displayApp ? (displayApp.name || appId) : appId
            showBackButton: true
            showBottomBar: true
            onBackClicked: navStack.pop()

            Component.onCompleted: {
                if (appId)
                    root.loadAppstream(appId, function (data) {
                        detailRoot.fullApp = data;
                    });
            }

            content: ColumnLayout {
                width: parent ? parent.width : 0
                spacing: MSpacing.lg

                // Hero block: brand colour + screenshot tint + icon + name.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(220 * root.sf)
                    color: root.brandingColor(detailRoot.displayApp)
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: detailRoot.fullApp && detailRoot.fullApp.screenshots && detailRoot.fullApp.screenshots.length > 0 ? root.bestScreenshotSrc(detailRoot.fullApp.screenshots[0].sizes) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        opacity: 0.30
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(0, 0, 0, 0.10)
                            }
                            GradientStop {
                                position: 1.0
                                color: MColors.background
                            }
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: MSpacing.md
                        anchors.rightMargin: MSpacing.md
                        anchors.bottomMargin: -Math.round(32 * root.sf)
                        spacing: MSpacing.md

                        Rectangle {
                            Layout.preferredWidth: Math.round(96 * root.sf)
                            Layout.preferredHeight: Math.round(96 * root.sf)
                            radius: Constants.borderRadiusSmall
                            color: MColors.surface
                            border.color: MColors.border
                            border.width: 1
                            Image {
                                anchors.fill: parent
                                anchors.margins: 10
                                source: detailRoot.displayApp && detailRoot.displayApp.icon ? detailRoot.displayApp.icon : ""
                                sourceSize: Qt.size(192, 192)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Math.round(44 * root.sf)
                            spacing: 2
                            MLabel {
                                text: detailRoot.displayApp ? (detailRoot.displayApp.name || "") : ""
                                font.pixelSize: MTypography.sizeXLarge
                                font.weight: MTypography.weightBold
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: MSpacing.xs
                                MLabel {
                                    text: detailRoot.displayApp ? (detailRoot.displayApp.developer_name || "") : ""
                                    variant: "secondary"
                                    font.pixelSize: MTypography.sizeSmall
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: detailRoot.displayApp && detailRoot.displayApp.verification_verified === true
                                    Layout.preferredHeight: Math.round(22 * root.sf)
                                    Layout.preferredWidth: vDetailText.implicitWidth + MSpacing.sm * 2
                                    radius: Constants.borderRadiusSmall
                                    color: MColors.marathonTealBright
                                    MLabel {
                                        id: vDetailText
                                        anchors.centerIn: parent
                                        text: {
                                            const a = detailRoot.displayApp;
                                            if (!a)
                                                return "Verified";
                                            if (a.verification_login_provider === "github")
                                                return "GitHub verified";
                                            if (a.verification_login_provider === "gitlab")
                                                return "GitLab verified";
                                            if (a.verification_login_provider === "gnome")
                                                return "GNOME verified";
                                            if (a.verification_method === "website")
                                                return "Website verified";
                                            return "Verified";
                                        }
                                        color: MColors.bb10Black
                                        font.pixelSize: MTypography.sizeXSmall
                                        font.weight: MTypography.weightBold
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.preferredHeight: MSpacing.lg
                }

                // Summary line.
                MLabel {
                    text: detailRoot.displayApp ? (detailRoot.displayApp.summary || "") : ""
                    font.pixelSize: MTypography.sizeBody
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    wrapMode: Text.WordWrap
                }

                // Categories — AppStream <categories> rendered as chips. Helps
                // users orient ("Audio", "Graphics", "Office") at a glance.
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.xs
                    visible: detailRoot.displayApp && detailRoot.displayApp.categories && detailRoot.displayApp.categories.length > 0
                    Repeater {
                        model: detailRoot.displayApp ? (detailRoot.displayApp.categories || []) : []
                        delegate: Rectangle {
                            width: catChip.implicitWidth + MSpacing.md * 2
                            height: Math.round(26 * root.sf)
                            radius: Constants.borderRadiusSmall
                            color: MColors.bb10Elevated
                            border.color: MColors.border
                            border.width: 1
                            MLabel {
                                id: catChip
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: MTypography.sizeXSmall
                                font.weight: MTypography.weightMedium
                                variant: "secondary"
                            }
                        }
                    }
                }

                // Compatibility strip — AppStream <supports><control> and
                // <requires>/<recommends> tell us what input methods the app
                // supports. Critical on a mobile shell: an app that only does
                // pointing+keyboard is going to be awkward on touch.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.sm
                    visible: detailRoot.compatItems.length > 0
                    Repeater {
                        model: detailRoot.compatItems
                        delegate: Row {
                            spacing: MSpacing.xs / 2
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.icon
                                size: Constants.iconSizeSmall - 4
                                color: modelData.ok ? MColors.marathonTeal : MColors.warning
                            }
                            MLabel {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: MTypography.sizeXSmall
                                color: modelData.ok ? MColors.textPrimary : MColors.warning
                            }
                        }
                    }
                }

                // Progress bar — only visible during an install.
                MProgressBar {
                    visible: detailRoot.progress && (detailRoot.progress.state === "downloading" || detailRoot.progress.state === "deploying" || detailRoot.progress.state === "pending")
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    value: detailRoot.progress && detailRoot.progress.percent >= 0 ? detailRoot.progress.percent / 100 : 0
                    indeterminate: detailRoot.progress && detailRoot.progress.percent < 0
                }

                // Stats strip — omits fields that came back null rather than
                // showing an em-dash placeholder.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: 0
                    Repeater {
                        model: {
                            const app = detailRoot.displayApp;
                            if (!app)
                                return [];
                            const items = [];
                            if (app.developer_name)
                                items.push({
                                    label: "DEVELOPER",
                                    value: app.developer_name
                                });
                            items.push({
                                label: "LICENSE",
                                value: app.is_free_license ? "Free" : "Proprietary"
                            });
                            if (app.categories && app.categories.length > 0)
                                items.push({
                                    label: "CATEGORY",
                                    value: app.categories[0]
                                });
                            const sz = detailRoot.fmtBytes(app.installed_size || app.download_size);
                            if (sz)
                                items.push({
                                    label: "SIZE",
                                    value: sz
                                });
                            return items;
                        }
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            MLabel {
                                text: modelData.label
                                variant: "tertiary"
                                font.pixelSize: 10
                                font.letterSpacing: 0.8
                                Layout.alignment: Qt.AlignHCenter
                            }
                            MLabel {
                                text: modelData.value
                                font.pixelSize: MTypography.sizeXSmall
                                font.weight: MTypography.weightMedium
                                Layout.alignment: Qt.AlignHCenter
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // Screenshots — horizontal scroll, snap to item.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: MSpacing.sm
                    visible: detailRoot.fullApp && detailRoot.fullApp.screenshots && detailRoot.fullApp.screenshots.length > 0
                    MLabel {
                        text: "Screenshots"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: MTypography.weightDemiBold
                        Layout.leftMargin: MSpacing.md
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(280 * root.sf)
                        orientation: ListView.Horizontal
                        spacing: MSpacing.sm
                        clip: true
                        leftMargin: MSpacing.md
                        rightMargin: MSpacing.md
                        cacheBuffer: width * 2
                        model: detailRoot.fullApp ? detailRoot.fullApp.screenshots : []
                        snapMode: ListView.SnapToItem
                        flickDeceleration: MMotion.touchFlickDeceleration
                        maximumFlickVelocity: MMotion.touchFlickVelocity
                        delegate: Rectangle {
                            width: Math.round(380 * root.sf)
                            height: Math.round(260 * root.sf)
                            radius: Constants.borderRadiusSmall
                            color: MColors.bb10Card
                            border.color: MColors.border
                            border.width: 1
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: root.bestScreenshotSrc(modelData.sizes)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }
                            // AppStream screenshots can carry a caption that
                            // describes what the shot shows — surface it as a
                            // legible footer so the row isn't just thumbnails.
                            Rectangle {
                                visible: modelData.caption && modelData.caption.length > 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: captionLabel.implicitHeight + MSpacing.sm * 2
                                color: Qt.rgba(0, 0, 0, 0.55)
                                MLabel {
                                    id: captionLabel
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: MSpacing.sm
                                    anchors.rightMargin: MSpacing.sm
                                    text: modelData.caption || ""
                                    color: "white"
                                    font.pixelSize: MTypography.sizeXSmall
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // About — title + wrapped description. MSection bound `height`
                // (not implicitHeight) doesn't survive ColumnLayout, so we
                // inline the section structure here. The card surface comes
                // from a child Rectangle that we size explicitly.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.sm
                    MLabel {
                        text: "About"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: MTypography.weightDemiBold
                    }
                    MLabel {
                        text: detailRoot.fullApp && detailRoot.fullApp.description ? detailRoot.fullApp.description.replace(/<[^>]+>/g, "").trim() : (detailRoot.displayApp && detailRoot.displayApp.description ? detailRoot.displayApp.description.replace(/<[^>]+>/g, "").trim() : "")
                        variant: "secondary"
                        font.pixelSize: MTypography.sizeSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                        Layout.fillWidth: true
                    }
                }

                // What's new — release notes from the latest entry.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.sm
                    visible: detailRoot.latestRelease !== null
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: MSpacing.sm
                        MLabel {
                            text: detailRoot.latestRelease && detailRoot.latestRelease.version ? "What's new — v" + detailRoot.latestRelease.version : "What's new"
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: MTypography.weightDemiBold
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        MLabel {
                            visible: detailRoot.latestRelease && detailRoot.latestRelease.date
                            text: detailRoot.latestRelease ? Qt.formatDate(new Date(detailRoot.latestRelease.date), "MMM d, yyyy") : ""
                            variant: "tertiary"
                            font.pixelSize: MTypography.sizeXSmall
                        }
                    }
                    MLabel {
                        text: detailRoot.latestRelease && detailRoot.latestRelease.description ? detailRoot.latestRelease.description.replace(/<[^>]+>/g, "").trim() : ""
                        visible: text.length > 0
                        variant: "secondary"
                        font.pixelSize: MTypography.sizeSmall
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                        Layout.fillWidth: true
                    }
                }

                // Information — title + a card surface containing each row.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.sm
                    visible: detailRoot.infoRows.length > 0

                    MLabel {
                        text: "Information"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: MTypography.weightDemiBold
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: infoCol.implicitHeight
                        color: MColors.bb10Card
                        radius: Constants.borderRadiusSmall
                        border.width: 1
                        border.color: MColors.border
                        Column {
                            id: infoCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            Repeater {
                                model: detailRoot.infoRows
                                delegate: MSettingsListItem {
                                    title: modelData.k
                                    value: modelData.v
                                    iconName: modelData.ic
                                    showChevron: false
                                    showDivider: index < detailRoot.infoRows.length - 1
                                }
                            }
                        }
                    }
                }

                // Permissions — same pattern as Information.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.sm
                    visible: detailRoot.permissionItems.length > 0

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        MLabel {
                            text: "Permissions"
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: MTypography.weightDemiBold
                        }
                        MLabel {
                            text: "What this app will be allowed to do"
                            variant: "secondary"
                            font.pixelSize: MTypography.sizeXSmall
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: permCol.implicitHeight
                        color: MColors.bb10Card
                        radius: Constants.borderRadiusSmall
                        border.width: 1
                        border.color: MColors.border
                        Column {
                            id: permCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            Repeater {
                                model: detailRoot.permissionItems
                                delegate: MSettingsListItem {
                                    title: modelData.label
                                    subtitle: modelData.detail
                                    iconName: modelData.icon
                                    showChevron: false
                                    showDivider: index < detailRoot.permissionItems.length - 1
                                }
                            }
                        }
                    }
                }

                // Links — homepage / bug tracker / donation / etc, rendered
                // as MSettingsListItem rows (matching the rest of the page).
                // A Flow of MButtons looked off: too small, text didn't read.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    spacing: MSpacing.sm
                    visible: detailRoot.linkRows.length > 0
                    MLabel {
                        text: "Project links"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: MTypography.weightDemiBold
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: linkCol.implicitHeight
                        color: MColors.bb10Card
                        radius: Constants.borderRadiusSmall
                        border.width: 1
                        border.color: MColors.border
                        Column {
                            id: linkCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            Repeater {
                                model: detailRoot.linkRows
                                delegate: MSettingsListItem {
                                    title: modelData.label
                                    subtitle: modelData.url
                                    iconName: modelData.ic
                                    showChevron: true
                                    showDivider: index < detailRoot.linkRows.length - 1
                                    onSettingClicked: Qt.openUrlExternally(modelData.url)
                                }
                            }
                        }
                    }
                }

                // Uninstall — only shown when already installed; lives at the
                // bottom of the body, not the bottom bar, so it doesn't fight
                // the primary CTA for attention.
                MButton {
                    visible: root.isInstalled(detailRoot.appId) && !(detailRoot.progress && (detailRoot.progress.state === "downloading" || detailRoot.progress.state === "deploying"))
                    text: "Uninstall"
                    variant: "secondary"
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    onClicked: root.uninstallApp(detailRoot.appId)
                }

                Item {
                    Layout.preferredHeight: MSpacing.lg
                }
            }

            // Primary CTA — single big button in the bottom bar. Label and
            // action switch based on state (install/open/update/installing).
            bottomBarContent: Rectangle {
                width: parent.width
                height: Math.round(72 * root.sf)
                color: MColors.elevated
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                MButton {
                    id: ctaButton
                    anchors.fill: parent
                    anchors.margins: MSpacing.sm
                    variant: "primary"
                    text: {
                        if (detailRoot.progress && detailRoot.progress.state === "downloading")
                            return "Installing… " + (detailRoot.progress.percent >= 0 ? (detailRoot.progress.percent + "%") : "");
                        if (detailRoot.progress && detailRoot.progress.state === "deploying")
                            return "Deploying…";
                        if (detailRoot.progress && detailRoot.progress.state === "pending")
                            return "Starting…";
                        if (root.hasUpdate(detailRoot.appId))
                            return "Update";
                        if (root.isInstalled(detailRoot.appId))
                            return "Open";
                        return "Install";
                    }
                    disabled: detailRoot.progress && (detailRoot.progress.state === "downloading" || detailRoot.progress.state === "deploying" || detailRoot.progress.state === "pending")
                    onClicked: {
                        MHaptics.mediumImpact();
                        if (root.hasUpdate(detailRoot.appId)) {
                            root.trackInstall(detailRoot.appId);
                            Qt.openUrlExternally("marathon-store://update/" + detailRoot.appId);
                        } else if (root.isInstalled(detailRoot.appId)) {
                            Qt.openUrlExternally("marathon-store://open/" + detailRoot.appId);
                        } else {
                            root.installApp(detailRoot.appId);
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------------
    // Search page (pushed onto the stack when the user submits the query).
    // --------------------------------------------------------------------
    Component {
        id: searchPage

        MPage {
            id: searchRoot
            property string initialQuery: ""
            property var results: []
            property bool searching: false
            property string searchError: ""

            title: "Search"
            showBackButton: true
            onBackClicked: navStack.pop()

            function runSearch(q) {
                if (!q || q.length === 0) {
                    searchRoot.results = [];
                    return;
                }
                searchRoot.searching = true;
                searchRoot.searchError = "";
                root.fetchJson(root.flathubApi + "/search", {
                    "query": q,
                    "filters": []
                }, function (data, err) {
                    searchRoot.searching = false;
                    if (err) {
                        searchRoot.searchError = err;
                        searchRoot.results = [];
                        return;
                    }
                    searchRoot.results = root.pickAarch64(data.hits || []);
                });
            }

            Component.onCompleted: if (initialQuery) {
                queryField.text = initialQuery;
                runSearch(initialQuery);
            }

            content: ColumnLayout {
                width: parent ? parent.width : 0
                spacing: MSpacing.sm

                Row {
                    Layout.fillWidth: true
                    Layout.leftMargin: MSpacing.md
                    Layout.rightMargin: MSpacing.md
                    Layout.topMargin: MSpacing.sm
                    spacing: MSpacing.sm

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: Constants.iconSizeSmall
                        color: MColors.textSecondary
                    }
                    MTextInput {
                        id: queryField
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.spacing * 2 - Constants.iconSizeSmall - (sClearBtn.visible ? sClearBtn.width + parent.spacing : 0)
                        placeholderText: "Search Flathub"
                        a11yName: "Search Flathub catalog"
                        onTextChanged: if (text.length >= 2)
                            searchRoot.runSearch(text)
                        else
                            searchRoot.results = []
                    }
                    MIconButton {
                        id: sClearBtn
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "x"
                        iconSize: Constants.iconSizeSmall
                        variant: "secondary"
                        a11yName: "Clear search"
                        visible: queryField.text.length > 0
                        onClicked: queryField.text = ""
                    }
                }

                MActivityIndicator {
                    visible: searchRoot.searching
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: MSpacing.lg
                }

                MEmptyState {
                    visible: !searchRoot.searching && searchRoot.results.length === 0 && queryField.text.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: MSpacing.xl
                    iconName: "search"
                    title: "No results"
                    message: "Try a different word or spelling."
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: Math.round(600 * root.sf)
                    interactive: true
                    clip: true
                    model: searchRoot.results
                    delegate: MSettingsListItem {
                        title: modelData.name || modelData.app_id
                        subtitle: modelData.summary || modelData.app_id
                        iconName: "package"
                        showChevron: true
                        onSettingClicked: root.openDetail(modelData)
                    }
                }
            }
        }
    }
}
