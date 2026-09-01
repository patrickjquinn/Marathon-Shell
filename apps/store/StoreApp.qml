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

// Marathon Store — Flathub-backed catalog with the JSX-spec UI.
//
// Data layer is the duranium-build implementation: XHR to flathub.org's
// v2 API for collections + appstream metadata + app-of-the-day, installs
// dispatched through the marathon-store:// URL scheme so the system-level
// shell handler (scripts/store/marathon-store-handler on this repo,
// /usr/libexec on Duranium) runs flatpak with progress JSON tracked in
// $XDG_RUNTIME_DIR.
//
// Visual layer follows screens-apps-1.jsx:StoreDiscover:
//   - "Store" title (not per-tab) with search + 32 px avatar
//   - EDITORS' PICK hero: diagonal teal-to-black gradient, top-right
//     radial teal glow, EDITORS' PICK chip, title + author/pricing,
//     Get + Preview. Text-first, no screenshot overlay.
//   - "Trending now" 3-up vertical grid (real flathub icons; falls
//     back to a tinted-square + Lucide glyph if the icon URL is
//     unreachable, so the layout never collapses)
//   - "Updates available · N" card with rows showing icon + name +
//     release notes · download size + Update button
//   - 4-tab bottom bar: Discover / Apps / Installed / Account
MApp {
    id: root

    appId: "store"
    appName: "App Store"
    appIcon: "assets/icon.svg"

    readonly property string flathubApi: "https://flathub.org/api/v2"
    readonly property string stateDir: "/run/user/" + (typeof userUid !== "undefined" ? userUid : "1000") + "/marathon-store-state"
    readonly property real sf: Constants.scaleFactor || 1.0

    property var collections: ({})
    property var appOfTheDay: null
    property var appstreamCache: ({})
    property var installedApps: []
    property var pendingUpdates: []
    property var installState: ({})
    property bool catalogLoading: false
    property string lastError: ""

    // Collections can come back with keys but zero entries: a fetch that
    // succeeded whose hits all failed the aarch64 filter still writes
    // collections["popular"] = []. Testing Object.keys().length treated
    // that as "catalog loaded", so the spinner stopped AND the empty state
    // stayed hidden, and Discover rendered a black void with no spinner,
    // no message and no way to tell it had failed. Count apps, not keys.
    readonly property int catalogAppCount: {
        let n = 0;
        for (const k in collections)
            n += (collections[k] || []).length;
        return n;
    }
    property int activeTab: 0

    signal openDetailRequested(string appId, var summary)

    // ── flathub.org HTTP layer ─────────────────────────────────
    //
    // Every outbound fetch is pinned to flathub.org and every Image
    // source is clamped to dl.flathub.org / flathub.org — keeps a
    // poisoned API response from steering us at a LAN host or
    // file:// URL via crafted icon/screenshot URLs.

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

    function isFlathubUrl(u) {
        return typeof u === "string" && u.indexOf("https://flathub.org/") === 0;
    }

    function safeImageUrl(u) {
        if (typeof u !== "string")
            return "";
        if (u.indexOf("https://dl.flathub.org/") === 0)
            return u;
        if (u.indexOf("https://flathub.org/") === 0)
            return u;
        return "";
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
        // 8 s timeout — long enough to ride out a slow 4G handshake on
        // a recently-resumed modem, short enough that an offline device
        // surfaces the "no catalog yet" empty state without leaving the
        // user staring at a stuck spinner. The previous 15 s ceiling
        // read as "the Store is broken" by the time it fired.
        const timer = Qt.createQmlObject('import QtQuick; Timer { interval: 8000; repeat: false }', root);
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

    // Hero pick: AOTD when loaded, else the first item from any
    // loaded collection (verified → popular → trending → mobile).
    // Falls back to null so the hero hides on first paint and
    // shows the moment a collection lands.
    function pickHeroApp() {
        if (root.appOfTheDay)
            return root.appOfTheDay;
        const order = ["verified", "popular", "trending", "mobile"];
        for (let i = 0; i < order.length; i++) {
            const list = root.collections[order[i]];
            if (list && list.length > 0)
                return list[0];
        }
        return null;
    }

    // Trending tiles: pull from the trending collection, skip the
    // hero pick, take the first 3. The 3-up vertical grid is the
    // JSX shape — duranium's horizontal-scroll rails are out.
    function pickTrendingApps(heroApp) {
        const list = root.collections["trending"] || [];
        const heroId = heroApp ? (heroApp.app_id || heroApp.id) : "";
        const out = [];
        for (let i = 0; i < list.length && out.length < 3; i++) {
            const id = list[i].app_id || list[i].id;
            if (id && id !== heroId)
                out.push(list[i]);
        }
        return out;
    }

    // Returns a human-readable category for a trending entry.
    // Collection responses don't include categories per-hit, so we
    // opportunistically fetch the appstream payload for each trending
    // app — the category lands ~150 ms after first paint and the
    // tile re-renders. `_categoryTick` is bumped on each cache write
    // so QML re-evaluates the binding.
    property int _categoryTick: 0
    property var _categoryFor: ({})

    function categoryForApp(app) {
        const _ = root._categoryTick;
        if (!app)
            return "App";
        const id = app.app_id || app.id || "";
        if (root._categoryFor[id])
            return root._categoryFor[id];
        // Fall back to in-band metadata if the collection endpoint
        // happened to include it (it usually doesn't).
        if (app.categories && app.categories.length > 0)
            return app.categories[0];
        // Lazy-fetch the appstream and cache the result.
        if (id && !root._categoryFor["__inflight__" + id]) {
            const next = Object.assign({}, root._categoryFor);
            next["__inflight__" + id] = true;
            root._categoryFor = next;
            root.loadAppstream(id, function (full) {
                if (!full)
                    return;
                let cat = "App";
                if (full.categories && full.categories.length > 0)
                    cat = full.categories[0];
                else if (full.main_categories && full.main_categories.length > 0)
                    cat = full.main_categories[0];
                else if (full.project_group)
                    cat = full.project_group;
                const after = Object.assign({}, root._categoryFor);
                after[id] = cat;
                delete after["__inflight__" + id];
                root._categoryFor = after;
                root._categoryTick = root._categoryTick + 1;
            });
        }
        return "App";
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

    // Stagger startup XHRs so we don't slam Flathub with parallel
    // requests on first paint.
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
                root.loadCollection("verified");
            }, function () {
                root.loadCollection("trending");
            }, function () {
                root.loadCollection("popular");
            }, function () {
                root.loadCollection("mobile");
            }, function () {
                root.refreshState();
            }];
        startupTimer.running = true;
    }

    // ── Presentation ───────────────────────────────────────────

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        // Derived hero + trending bound at the page level so they
        // re-evaluate when collections / AOTD finishes loading.
        readonly property var heroApp: root.appOfTheDay || (root.collections["verified"] && root.collections["verified"][0]) || (root.collections["popular"] && root.collections["popular"][0]) || (root.collections["trending"] && root.collections["trending"][0]) || null
        readonly property var trendingApps: root.pickTrendingApps(heroApp)

        MStackView {
            id: navStack
            anchors.fill: parent
            initialItem: homeShell
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

        Component {
            id: homeShell

            Item {
                anchors.fill: parent

                Column {
                    id: shellCol
                    anchors.fill: parent
                    spacing: 0

                    // ── Top bar ────────────────────────────────
                    MTopBar {
                        id: topBar
                        width: parent.width
                        title: "Store"
                        actions: [
                            Icon {
                                name: "search"
                                size: 22
                                color: MColors.textSecondary
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -10
                                    onClicked: HapticService.light()
                                }
                            },
                            Rectangle {
                                width: 32
                                height: 32
                                radius: width / 2
                                color: MColors.elev3
                                border.width: 1
                                border.color: MColors.whiteOverlay08
                                Icon {
                                    anchors.centerIn: parent
                                    name: "user"
                                    size: 16
                                    color: MColors.textSecondary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: HapticService.light()
                                }
                            }
                        ]
                    }

                    // ── Tabbed content area ────────────────────
                    StackLayout {
                        id: tabStack
                        width: parent.width
                        height: parent.height - topBar.height - tabBar.height
                        currentIndex: root.activeTab

                        // 0 — Discover
                        Loader {
                            sourceComponent: discoverPage
                            active: true
                        }
                        // 1 — Apps (search-style category browser)
                        Loader {
                            sourceComponent: appsPage
                            active: root.activeTab === 1 || root.collections["popular"]
                        }
                        // 2 — Installed
                        Loader {
                            sourceComponent: installedPage
                            active: root.activeTab === 2 || root.installedApps.length > 0
                        }
                        // 3 — Account
                        Loader {
                            sourceComponent: accountPage
                            active: root.activeTab === 3
                        }
                    }

                    MTabBar {
                        id: tabBar
                        width: parent.width
                        activeTab: root.activeTab
                        tabs: [
                            {
                                "label": "Discover",
                                "icon": "compass"
                            },
                            {
                                "label": "Apps",
                                "icon": "grid"
                            },
                            {
                                "label": "Installed",
                                "icon": "download"
                            },
                            {
                                "label": "Account",
                                "icon": "user"
                            }
                        ]
                        onTabSelected: index => {
                            HapticService.light();
                            root.activeTab = index;
                            if (index === 2)
                                root.refreshState();
                        }
                    }
                }
            }
        }

        // ── Discover page (JSX layout) ─────────────────────────
        //
        // EDITORS' PICK hero → Trending now 3-tile grid → Updates
        // available rows. Vertical stack inside a Flickable so the
        // page scrolls cleanly on shorter screens.
        Component {
            id: discoverPage

            Flickable {
                contentWidth: width
                contentHeight: discoverCol.height + 20
                clip: true

                Column {
                    id: discoverCol
                    width: parent.width
                    topPadding: 16
                    spacing: 18

                    // ── EDITORS' PICK hero ────────────────────
                    // Per screens-apps-1.jsx:StoreDiscover. Diagonal
                    // teal-to-black background, 220 px radial teal-
                    // bright glow bleeding into the upper-right
                    // third, text-only foreground (no screenshot
                    // overlay — that's the duranium app-of-the-day
                    // hero, which is a different design language).
                    Item {
                        id: heroSlot
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        height: 200
                        visible: navStack.parent.heroApp !== null
                        clip: true

                        readonly property var hero: navStack.parent.heroApp

                        Rectangle {
                            anchors.fill: parent
                            radius: MRadius.md
                            border.width: 1
                            border.color: MColors.tealBorder
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop {
                                    position: 0
                                    color: "#1a4a3e"
                                }
                                GradientStop {
                                    position: 0.7
                                    color: "#040404"
                                }
                            }
                        }
                        // Radial teal glow on the top-right corner.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -60
                            anchors.rightMargin: -60
                            width: 220
                            height: 220
                            radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0
                                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.0)
                                }
                            }
                        }
                        // Top-edge inset highlight per DS.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 1
                            anchors.rightMargin: 1
                            anchors.topMargin: 1
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.10)
                        }

                        Column {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            anchors.topMargin: 16
                            anchors.bottomMargin: 16
                            spacing: 8

                            Rectangle {
                                width: pickText.implicitWidth + 16
                                height: 22
                                radius: 2
                                color: MColors.marathonTealBright
                                Text {
                                    id: pickText
                                    anchors.centerIn: parent
                                    text: "EDITORS' PICK"
                                    color: "#000000"
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                    font.weight: Font.Bold
                                    font.letterSpacing: MTypography.trackingEyebrow
                                }
                            }

                            Text {
                                width: parent.width
                                text: heroSlot.hero ? (heroSlot.hero.name || heroSlot.hero.app_id || "") : ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 22
                                font.weight: Font.Medium
                                font.letterSpacing: -0.3
                                lineHeight: 1.15
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: {
                                    if (!heroSlot.hero)
                                        return "";
                                    const author = heroSlot.hero.developer_name || heroSlot.hero.author || "";
                                    const summary = heroSlot.hero.summary || "";
                                    if (author && summary)
                                        return author + " · " + summary;
                                    return author || summary;
                                }
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Item {
                                width: parent.width
                                height: 4
                            }

                            Row {
                                spacing: 8
                                MButton {
                                    text: heroSlot.hero && root.isInstalled(heroSlot.hero.app_id || heroSlot.hero.id) ? "Open" : "Get"
                                    variant: "primary"
                                    size: "compact"
                                    onClicked: {
                                        if (!heroSlot.hero)
                                            return;
                                        const id = heroSlot.hero.app_id || heroSlot.hero.id;
                                        if (root.isInstalled(id))
                                            Qt.openUrlExternally("marathon-store://open/" + id);
                                        else
                                            root.installApp(id);
                                    }
                                }
                                MButton {
                                    text: "Preview"
                                    variant: "ghost"
                                    size: "compact"
                                    onClicked: {
                                        if (heroSlot.hero)
                                            root.openDetail(heroSlot.hero);
                                    }
                                }
                            }
                        }
                    }

                    // ── Trending now ──────────────────────────
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: navStack.parent.trendingApps.length > 0

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: "Trending now"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            font.letterSpacing: -0.2
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: "Top picks from across Flathub"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 8
                            spacing: 10

                            Repeater {
                                model: navStack.parent.trendingApps
                                delegate: Column {
                                    width: (parent.width - parent.spacing * 2) / 3
                                    spacing: 8

                                    // Real flathub icon at full bleed in a
                                    // 4 px-radius squircle. Falls back to a
                                    // tinted elev-3 square if the URL is
                                    // empty or the network image hasn't
                                    // resolved yet, so the row never
                                    // collapses to a row of blank rectangles.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width
                                        height: width
                                        radius: 4
                                        color: MColors.elev3
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.6)

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            source: root.safeImageUrl(modelData.icon || "")
                                            sourceSize: Qt.size(192, 192)
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                        }
                                        // Glyph fallback when the network
                                        // image hasn't landed.
                                        Icon {
                                            anchors.centerIn: parent
                                            visible: !modelData.icon || root.safeImageUrl(modelData.icon) === ""
                                            name: "package"
                                            size: 38
                                            color: MColors.textSecondary
                                        }
                                        // Top-edge inset highlight per DS.
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.leftMargin: 1
                                            anchors.rightMargin: 1
                                            anchors.topMargin: 1
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.15)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                HapticService.light();
                                                root.openDetail(modelData);
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        width: parent.width
                                        text: modelData.name || modelData.app_id || ""
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        width: parent.width
                                        text: {
                                            const cat = root.categoryForApp(modelData);
                                            const installs = modelData.installs_last_month;
                                            if (typeof installs === "number" && installs > 0)
                                                return cat + " · ★ " + (installs > 1000 ? (Math.round(installs / 1000)) + "k" : installs);
                                            return cat;
                                        }
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // ── Updates available ─────────────────────
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.pendingUpdates.length > 0

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: "Updates available · " + root.pendingUpdates.length
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            font.letterSpacing: -0.2
                        }

                        MCard {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            elevation: 2
                            height: updateRows.height + 8

                            Column {
                                id: updateRows
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: -10
                                anchors.rightMargin: -10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Repeater {
                                    model: root.pendingUpdates
                                    delegate: Item {
                                        width: parent.width
                                        height: 62

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 12

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 38
                                                height: 38
                                                radius: 4
                                                color: MColors.elev3
                                                border.width: 1
                                                border.color: Qt.rgba(0, 0, 0, 0.6)
                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    source: root.safeImageUrl(modelData.icon || "")
                                                    asynchronous: true
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                }
                                                Icon {
                                                    anchors.centerIn: parent
                                                    visible: !modelData.icon || root.safeImageUrl(modelData.icon) === ""
                                                    name: "package"
                                                    size: 18
                                                    color: MColors.textSecondary
                                                }
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 38 - 92 - parent.spacing * 2
                                                spacing: 2
                                                Text {
                                                    text: modelData.name || modelData.app_id
                                                    color: MColors.textPrimary
                                                    font.family: MTypography.fontFamily
                                                    font.pixelSize: MTypography.sizeSubhead
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                                Text {
                                                    width: parent.width
                                                    text: "Update available"
                                                    color: MColors.textSecondary
                                                    font.family: MTypography.fontFamily
                                                    font.pixelSize: MTypography.sizeFootnote
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MButton {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Update"
                                                variant: "primary"
                                                size: "compact"
                                                onClicked: root.installApp(modelData.app_id)
                                            }
                                        }

                                        Rectangle {
                                            visible: index < root.pendingUpdates.length - 1
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 14 + 38 + 12
                                            anchors.rightMargin: 14
                                            height: 1
                                            color: MColors.whiteOverlay04
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Activity spinner while collections are
                    // loading on first paint.
                    MActivityIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.catalogLoading && root.catalogAppCount === 0 && !navStack.parent.heroApp
                    }

                    // Same MEmptyState the Apps tab uses, surfaced here
                    // when the Discover hero collection also failed to
                    // load (offline device, DNS blocked, Flathub down).
                    // Without this the Discover tab silently sat empty
                    // after the spinner gave up.
                    // centerIn is illegal on a Column child and breaks the
                    // whole Discover column; horizontalCenter is allowed.
                    MEmptyState {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 48
                        visible: !root.catalogLoading && root.catalogAppCount === 0 && !navStack.parent.heroApp
                        iconName: "wifi-off"
                        iconSize: 64
                        title: "Can't reach Flathub"
                        message: "Check your network connection and pull down to retry."
                    }
                }
            }
        }

        // ── Apps tab — search-driven browse ─────────────────────
        //
        // Flathub doesn't have a single "all apps" feed; the v2 API
        // is collection-driven (popular, recently-added, …). The
        // Apps tab here surfaces the Popular collection as a
        // browseable list, with the trending entries dropped so it
        // doesn't duplicate the Discover hero/trending. A future
        // iteration can layer a search field on top and call
        // flathub.org/api/v2/search.
        Component {
            id: appsPage

            Rectangle {
                color: MColors.background

                ListView {
                    id: appsList
                    anchors.fill: parent
                    anchors.topMargin: 8
                    clip: true
                    spacing: 0
                    // Leave clearance for the tab bar's halo + home
                    // indicator so the last list item's Get button
                    // doesn't crowd the active-tab radial glow.
                    bottomMargin: 16
                    model: root.collections["popular"] || []
                    visible: model.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 76

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 14

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 56
                                height: 56
                                radius: 6
                                color: MColors.elev3
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.6)
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    source: root.safeImageUrl(modelData.icon || "")
                                    sourceSize: Qt.size(128, 128)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !modelData.icon || root.safeImageUrl(modelData.icon) === ""
                                    name: "package"
                                    size: 24
                                    color: MColors.textSecondary
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 56 - 80 - parent.spacing * 2
                                spacing: 2
                                Text {
                                    text: modelData.name || modelData.app_id
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeSubhead
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    text: modelData.summary || modelData.developer_name || ""
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    width: parent.width
                                }
                            }

                            MButton {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.isInstalled(modelData.app_id) ? "Open" : "Get"
                                variant: root.isInstalled(modelData.app_id) ? "secondary" : "primary"
                                size: "compact"
                                onClicked: {
                                    const id = modelData.app_id || modelData.id;
                                    if (root.isInstalled(id))
                                        Qt.openUrlExternally("marathon-store://open/" + id);
                                    else
                                        root.installApp(id);
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 16 + 56 + 14
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: MColors.whiteOverlay04
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: {
                                HapticService.light();
                                root.openDetail(modelData);
                            }
                        }
                    }
                }

                MEmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    // Mirrors the ListView's own `visible: model.length > 0`
                    // above, so the list and its empty state can never both
                    // be hidden -- the split-predicate shape that left
                    // Discover rendering a void with nothing to explain it.
                    visible: !appsList.visible && !root.catalogLoading
                    iconName: "grid"
                    iconSize: 64
                    title: "No catalog yet"
                    message: "The Flathub catalog hasn't loaded. Check your network and try the refresh button in Discover."
                }
            }
        }

        // ── Installed tab ──────────────────────────────────────
        Component {
            id: installedPage

            Rectangle {
                color: MColors.background
                Component.onCompleted: root.loadInstalled()

                ListView {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    clip: true
                    spacing: 0
                    visible: root.installedApps.length > 0
                    model: root.installedApps

                    delegate: Item {
                        width: ListView.view.width
                        height: 68

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 14

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 48
                                height: 48
                                radius: 6
                                color: MColors.elev3
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.6)
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    // marathon-store-refresh-state emits
                                    // file:// URLs to PNGs in
                                    // ~/.local/share/flatpak/exports/share/icons/…
                                    // Local paths bypass the SSRF clamp
                                    // because they were written by the
                                    // shell-handler script.
                                    source: modelData.icon || ""
                                    sourceSize: Qt.size(96, 96)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !modelData.icon
                                    name: "package"
                                    size: 22
                                    color: MColors.textSecondary
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 48 - parent.spacing
                                spacing: 2
                                Text {
                                    text: modelData.name || modelData.app_id
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeSubhead
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    text: modelData.version ? ("v" + modelData.version) : modelData.app_id
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 16 + 48 + 14
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: MColors.whiteOverlay04
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticService.light();
                                root.openDetail(modelData);
                            }
                        }
                    }
                }

                MEmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    visible: root.installedApps.length === 0
                    iconName: "download"
                    iconSize: 64
                    title: "Nothing installed yet"
                    message: "Tap Discover to find your first app from Flathub."
                }
            }
        }

        // ── Account tab — placeholder until identity lands ─────
        Component {
            id: accountPage

            Rectangle {
                color: MColors.background
                MEmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    iconName: "user"
                    iconSize: 64
                    title: "Marathon Account"
                    message: "Sign-in, billing, and purchase history will appear here once Marathon identity lands. For now Flathub installs go through the system flatpak user remote."
                }
            }
        }

        // ── Detail page (lightweight; full screen) ─────────────
        Component {
            id: detailPage

            Rectangle {
                property string appId: ""
                property var summaryApp: null
                property var fullApp: null
                readonly property var displayApp: fullApp || summaryApp

                color: MColors.background
                Component.onCompleted: {
                    if (appId)
                        root.loadAppstream(appId, function (data) {
                            fullApp = data;
                        });
                }

                Column {
                    anchors.fill: parent
                    spacing: 0

                    // No back-chevron in `actions:` — Marathon apps use
                    // the shell's swipe-back gesture (root.backPressed
                    // → navStack.pop()) for consistency with Settings,
                    // Phone, Notes, etc.
                    MTopBar {
                        width: parent.width
                        title: displayApp ? (displayApp.name || appId) : appId
                    }

                    Flickable {
                        width: parent.width
                        height: parent.height - 96
                        clip: true
                        contentHeight: detailCol.height + 20

                        Column {
                            id: detailCol
                            width: parent.width
                            topPadding: 16
                            spacing: 16

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                spacing: 14

                                Rectangle {
                                    width: 88
                                    height: 88
                                    radius: 8
                                    color: MColors.elev3
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.6)
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        source: displayApp ? root.safeImageUrl(displayApp.icon || "") : ""
                                        sourceSize: Qt.size(192, 192)
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text {
                                        text: displayApp ? (displayApp.name || appId) : ""
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: 22
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: displayApp ? (displayApp.developer_name || displayApp.author || "") : ""
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: 13
                                    }
                                    MButton {
                                        text: displayApp && root.isInstalled(appId) ? "Open" : "Get"
                                        variant: "primary"
                                        size: "compact"
                                        onClicked: {
                                            if (root.isInstalled(appId))
                                                Qt.openUrlExternally("marathon-store://open/" + appId);
                                            else
                                                root.installApp(appId);
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                width: parent.width - 32
                                text: displayApp ? (displayApp.summary || "") : ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                width: parent.width - 32
                                text: displayApp ? (displayApp.description || "").replace(/<[^>]+>/g, "") : ""
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}
