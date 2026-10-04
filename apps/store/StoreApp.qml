import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
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

    // The JSX spec is drawn at scale 1. Sizes with no MSpacing / MRadius /
    // MTypography token go through here, or they stay at design size while
    // the tokenised chrome around them grows with the display's DPI.
    function dp(n) {
        return Math.round(n * root.sf);
    }

    // Flathub icon in the DS tile: elev-3 square, black hairline, top-edge
    // highlight. The glyph shows until the image is Ready, so a slow or
    // failed fetch reads as a placeholder rather than an empty box.
    component AppIcon: Rectangle {
        id: tile

        property url source
        // Retried because a lookup can fail while the resolver settles after
        // boot or resume, and a pooled runner outlives that. Each retry changes
        // only the fragment: never sent to the server, but a new pixmap-cache
        // key, so Image refetches.
        property int attempt: 0

        onSourceChanged: attempt = 0
        radius: MRadius.md
        color: MColors.elev3
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.6)

        Image {
            id: img
            anchors.fill: parent
            anchors.margins: Math.round(parent.width * 0.12)
            source: tile.source.toString() === "" ? "" : tile.source + (tile.attempt > 0 ? "#retry" + tile.attempt : "")
            sourceSize: Qt.size(192, 192)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Timer {
            interval: 3000 * (tile.attempt + 1)
            running: img.status === Image.Error && tile.attempt < 3
            onTriggered: tile.attempt++
        }
        Icon {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            name: "package"
            size: Math.round(parent.width * 0.42)
            color: MColors.textSecondary
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 1
            color: Qt.rgba(1, 1, 1, 0.15)
        }
    }

    // DS list card: icon + title + subtitle + compact action per row, with
    // hairline dividers inset past the icon. Inline components cannot see
    // `root`, hence the local scale factor and the caller-supplied icon URL.
    component AppRowCard: MCard {
        id: card

        property var model: []
        property var iconFor: app => ""
        property var subtitleFor: app => ""
        property var actionFor: app => ""
        readonly property real sf: Constants.scaleFactor || 1.0

        signal actionClicked(var app)
        signal rowClicked(var app)

        elevation: 2
        height: rows.height

        // MCard insets its content by MSpacing.md; the rows run edge to edge.
        Column {
            id: rows
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -MSpacing.md

            Repeater {
                model: card.model
                delegate: Item {
                    width: rows.width
                    height: Math.round(62 * card.sf)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            card.rowClicked(modelData);
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(14 * card.sf)
                        anchors.rightMargin: Math.round(14 * card.sf)
                        spacing: Math.round(12 * card.sf)

                        AppIcon {
                            id: rowIcon
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(38 * card.sf)
                            height: width
                            source: card.iconFor(modelData)
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - rowIcon.width - rowAction.width - parent.spacing * 2
                            Text {
                                width: parent.width
                                text: modelData.name || modelData.app_id || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: card.subtitleFor(modelData)
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                elide: Text.ElideRight
                            }
                        }

                        MButton {
                            id: rowAction
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.actionFor(modelData)
                            variant: "primary"
                            size: "compact"
                            onClicked: card.actionClicked(modelData)
                        }
                    }

                    Rectangle {
                        visible: index < card.model.length - 1
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Math.round((14 + 38 + 12) * card.sf)
                        anchors.rightMargin: Math.round(14 * card.sf)
                        height: 1
                        color: MColors.whiteOverlay04
                    }
                }
            }
        }
    }

    property var collections: ({})
    property var appOfTheDay: null
    property var appstreamCache: ({})
    property var installedApps: []
    property var pendingUpdates: []
    property var installState: ({})
    // Four collections load concurrently, so this has to count fetches in
    // flight, not be a bool. As a bool the FIRST response cleared it while
    // three were still running: with the app-counting guard that means a
    // healthy device can flash "Can't reach Flathub" for a second if the
    // first collection back happens to filter to zero aarch64 hits.
    property int catalogFetchesInFlight: 0
    readonly property bool catalogLoading: catalogFetchesInFlight > 0
    // Why the CATALOG failed to load -- surfaced on Discover's empty state,
    // and cleared as soon as a collection lands. Install failures go to
    // installError; they used to share this and made the "Can't reach
    // Flathub" card blame an unrelated bad install ref.
    property string lastError: ""
    property string installError: ""

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

        // The timeout path calls abort(), and abort() itself drives
        // onreadystatechange to DONE -- so a timing-out request used to
        // invoke cb twice, once as "timeout" and again as "HTTP 0". Callers
        // that only set a flag did not notice; a caller that counts
        // requests in flight would be driven negative and never report
        // loading again. Deliver exactly one result per request.
        let settled = false;
        function settle(data, err) {
            if (settled)
                return;
            settled = true;
            timer.stop();
            timer.destroy();
            if (err)
                console.warn("[Store] fetch failed:", url, "--", err);
            cb(data, err);
        }

        timer.triggered.connect(function () {
            xhr.abort();
            settle(null, "timeout");
        });
        timer.start();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                settle(null, "HTTP " + xhr.status);
                return;
            }
            if (xhr.responseText.length > 1024 * 1024) {
                settle(null, "response too large");
                return;
            }
            try {
                settle(JSON.parse(xhr.responseText), null);
            } catch (e) {
                settle(null, "parse: " + e);
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
        catalogFetchesInFlight += 1;
        fetchJson(flathubApi + "/collection/" + name + "?page=1&per_page=24&locale=en", null, function (data, err) {
            root.catalogFetchesInFlight -= 1;
            if (err) {
                lastError = name + ": " + err;
                return;
            }
            const next = Object.assign({}, root.collections);
            next[name] = pickAarch64(data.hits || []);
            root.collections = next;
            root.lastError = "";
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

    function openDetail(app) {
        root.openDetailRequested(app.app_id || app.id, app);
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
            root.installError = "Refusing to install invalid ref: " + appId;
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

    // Made-for-phones rows: the mobile collection minus anything already
    // shown above it, so Discover never lists the same app twice.
    function pickMobileApps(heroApp, trending) {
        const shown = trending.map(a => a.app_id || a.id);
        if (heroApp)
            shown.push(heroApp.app_id || heroApp.id);
        const list = root.collections["mobile"] || [];
        const out = [];
        for (let i = 0; i < list.length && out.length < 5; i++) {
            const id = list[i].app_id || list[i].id;
            if (id && shown.indexOf(id) < 0)
                out.push(list[i]);
        }
        return out;
    }

    // A human-readable category for a trending entry. Collection responses
    // don't carry categories per hit, so the appstream payload is fetched
    // per app; the category lands ~150 ms after first paint and the tile
    // re-renders because `_categoryTick` is bumped on each cache write.
    //
    // Read and fetch are separate on purpose. They used to be one function
    // called straight from the tile's `text` binding, and it assigned
    // `_categoryFor` -- a property that same binding had just read. The
    // write dirtied the binding, QML re-evaluated it, it wrote again, and
    // Qt stopped it with "Binding loop detected for property text", nine
    // times over on a nine-tile grid. A binding has to be pure; the fetch
    // is now kicked off once per tile from Component.onCompleted.
    property int _categoryTick: 0
    property var _categoryFor: ({})

    // Pure: reads the cache, never writes it. Safe in a binding.
    function categoryLabel(app) {
        const _ = root._categoryTick;
        if (!app)
            return "App";
        const id = app.app_id || app.id || "";
        if (root._categoryFor[id])
            return root._categoryFor[id];
        // In-band metadata if the collection endpoint happened to include
        // it, which it usually does not.
        if (app.categories && app.categories.length > 0)
            return app.categories[0];
        return "App";
    }

    // Side-effecting: starts one appstream fetch per app. Call it from a
    // handler, never from a binding.
    function ensureCategory(app) {
        if (!app)
            return;
        const id = app.app_id || app.id || "";
        if (!id || root._categoryFor[id])
            return;
        if (root._categoryFor["__inflight__" + id])
            return;
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
        readonly property var mobileApps: root.pickMobileApps(heroApp, trendingApps)

        MStackView {
            id: navStack
            anchors.fill: parent
            initialItem: homeShell
            // MApp.handleBack only emits backPressed while navigationDepth > 0.
            onDepthChanged: root.navigationDepth = depth - 1
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
                                size: root.dp(22)
                                color: MColors.textSecondary
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -root.dp(10)
                                    onClicked: HapticService.light()
                                }
                            },
                            Rectangle {
                                width: root.dp(28)
                                height: width
                                radius: width / 2
                                color: MColors.elev3
                                border.width: 1
                                border.color: MColors.whiteOverlay08
                                Icon {
                                    anchors.centerIn: parent
                                    name: "user"
                                    size: root.dp(16)
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
                            active: root.activeTab === 1 || !!root.collections["popular"]
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
        // available rows → Made for phones. Vertical stack inside a
        // Flickable so the page scrolls cleanly on shorter screens.
        Component {
            id: discoverPage

            Flickable {
                id: discoverFlick
                contentWidth: width
                contentHeight: discoverCol.height + MSpacing.lg
                clip: true

                Column {
                    id: discoverCol
                    // Bound to the Flickable, not `parent`: a Flickable
                    // reparents its children onto contentItem, so
                    // `parent.width` here is the content item's width, not
                    // the viewport's. Every child below sizes off this, so
                    // getting it wrong collapses the entire page.
                    width: discoverFlick.width
                    topPadding: root.dp(14)
                    spacing: MSpacing.lg

                    // ── EDITORS' PICK hero ────────────────────
                    // Per screens-apps-1.jsx:StoreDiscover: 135° teal-to-
                    // black card with a radial teal glow bleeding in from the
                    // top-right, text-only foreground. Height follows the
                    // text, so a two-line name never clips the buttons.
                    Item {
                        id: heroSlot
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: MSpacing.md
                        anchors.rightMargin: MSpacing.md
                        height: heroText.implicitHeight + root.dp(18) * 2
                        visible: navStack.parent.heroApp !== null

                        readonly property var hero: navStack.parent.heroApp

                        // Both layers are painted in one Canvas clipped to the
                        // card's rounded rect: a Rectangle gradient can only
                        // run along an axis, and the glow would otherwise
                        // spill past the rounded corner it sits on.
                        Canvas {
                            id: heroBg
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d");
                                const r = MRadius.md;
                                ctx.clearRect(0, 0, width, height);
                                ctx.save();
                                ctx.beginPath();
                                ctx.roundedRect(0, 0, width, height, r, r);
                                ctx.clip();
                                const span = Math.max(width, height);
                                const bg = ctx.createLinearGradient(0, 0, span, span);
                                bg.addColorStop(0.0, "#1a4a3e");
                                bg.addColorStop(0.7, "#040404");
                                ctx.fillStyle = bg;
                                ctx.fillRect(0, 0, width, height);
                                // The spec's 200 px box sits 40 px off the right
                                // and 30 px off the top; CSS sizes a circle
                                // gradient to the box's farthest corner.
                                const gx = width - root.dp(60);
                                const gy = root.dp(70);
                                const glow = ctx.createRadialGradient(gx, gy, 0, gx, gy, root.dp(141));
                                glow.addColorStop(0.0, "rgba(0, 191, 165, 0.35)");
                                glow.addColorStop(0.6, "rgba(0, 191, 165, 0.0)");
                                ctx.fillStyle = glow;
                                ctx.fillRect(0, 0, width, height);
                                ctx.restore();
                            }
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: MRadius.md
                            color: "transparent"
                            border.width: 1
                            border.color: MColors.tealBorder
                        }
                        // Top-edge inset highlight per DS.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 1
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.10)
                        }

                        Column {
                            id: heroText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: root.dp(18)
                            spacing: 0

                            Rectangle {
                                width: pickText.implicitWidth + MSpacing.md
                                height: root.dp(22)
                                radius: MRadius.sm
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
                                topPadding: root.dp(12)
                                text: heroSlot.hero ? (heroSlot.hero.name || heroSlot.hero.app_id || "") : ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeTitle3
                                font.weight: Font.Medium
                                font.letterSpacing: MTypography.trackingTitle3
                                lineHeight: 1.15
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                topPadding: root.dp(8)
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
                                font.pixelSize: MTypography.sizeFootnote
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Row {
                                topPadding: root.dp(14)
                                spacing: root.dp(8)
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
                                    onClicked: root.openDetail(heroSlot.hero)
                                }
                            }
                        }
                    }

                    // ── Trending now ──────────────────────────
                    Column {
                        width: parent.width
                        spacing: 0
                        visible: navStack.parent.trendingApps.length > 0

                        Text {
                            x: MSpacing.md
                            text: "Trending now"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeHeadline
                            font.weight: Font.DemiBold
                            font.letterSpacing: MTypography.trackingHeadline
                        }
                        Text {
                            x: MSpacing.md
                            bottomPadding: root.dp(8)
                            text: "Top picks from across Flathub"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeCaption
                        }

                        Row {
                            x: MSpacing.md
                            width: parent.width - MSpacing.md * 2
                            spacing: MSpacing.sm

                            Repeater {
                                model: navStack.parent.trendingApps
                                delegate: Column {
                                    width: (parent.width - parent.spacing * 2) / 3
                                    spacing: 0

                                    Component.onCompleted: root.ensureCategory(modelData)

                                    AppIcon {
                                        width: parent.width
                                        height: width
                                        source: root.safeImageUrl(modelData.icon || "")
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                HapticService.light();
                                                root.openDetail(modelData);
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        topPadding: root.dp(8)
                                        text: modelData.name || modelData.app_id || ""
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: {
                                            const cat = root.categoryLabel(modelData);
                                            const installs = modelData.installs_last_month;
                                            if (typeof installs === "number" && installs > 0)
                                                return cat + " · ★ " + (installs > 1000 ? (Math.round(installs / 1000)) + "k" : installs);
                                            return cat;
                                        }
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeCaption
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // ── Updates available ─────────────────────
                    Column {
                        width: parent.width
                        spacing: root.dp(8)
                        visible: root.pendingUpdates.length > 0

                        Text {
                            x: MSpacing.md
                            text: "Updates available · " + root.pendingUpdates.length
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeHeadline
                            font.weight: Font.DemiBold
                            font.letterSpacing: MTypography.trackingHeadline
                        }

                        AppRowCard {
                            x: MSpacing.md
                            width: parent.width - MSpacing.md * 2
                            model: root.pendingUpdates
                            iconFor: app => root.safeImageUrl(app.icon || "")
                            subtitleFor: app => "Update available"
                            actionFor: app => "Update"
                            onActionClicked: app => root.installApp(app.app_id)
                            onRowClicked: app => root.openDetail(app)
                        }
                    }

                    // ── Made for phones ───────────────────────
                    // Flathub's mobile collection: apps that declare a
                    // phone form factor.
                    Column {
                        width: parent.width
                        spacing: root.dp(8)
                        visible: navStack.parent.mobileApps.length > 0

                        Text {
                            x: MSpacing.md
                            text: "Made for phones"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeHeadline
                            font.weight: Font.DemiBold
                            font.letterSpacing: MTypography.trackingHeadline
                        }

                        AppRowCard {
                            x: MSpacing.md
                            width: parent.width - MSpacing.md * 2
                            model: navStack.parent.mobileApps
                            iconFor: app => root.safeImageUrl(app.icon || "")
                            subtitleFor: app => app.summary || app.developer_name || ""
                            actionFor: app => root.isInstalled(app.app_id || app.id) ? "Open" : "Get"
                            onActionClicked: app => {
                                const id = app.app_id || app.id;
                                if (root.isInstalled(id))
                                    Qt.openUrlExternally("marathon-store://open/" + id);
                                else
                                    root.installApp(id);
                            }
                            onRowClicked: app => root.openDetail(app)
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
                    // Column rejects the VERTICAL anchors (top, bottom,
                    // verticalCenter, fill, centerIn); horizontalCenter is
                    // fine and is what MEmptyState uses internally. The void
                    // here was never an anchor problem -- MEmptyState had no
                    // implicitHeight, so it was a zero-height box that the
                    // clipping Flickable discarded.
                    MEmptyState {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: discoverCol.width - MSpacing.lg * 2
                        visible: !root.catalogLoading && root.catalogAppCount === 0 && !navStack.parent.heroApp
                        iconName: "wifi-slash"
                        iconSize: root.dp(64)
                        title: "Can't reach Flathub"
                        message: root.lastError !== "" ? "Check your network connection and pull down to retry.\n(" + root.lastError + ")" : "Check your network connection and pull down to retry."
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
                    anchors.topMargin: root.dp(8)
                    clip: true
                    spacing: 0
                    // Leave clearance for the tab bar's halo + home
                    // indicator so the last list item's Get button
                    // doesn't crowd the active-tab radial glow.
                    bottomMargin: MSpacing.md
                    model: root.collections["popular"] || []
                    visible: model.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: root.dp(76)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: MSpacing.md
                            anchors.rightMargin: MSpacing.md
                            spacing: root.dp(14)

                            AppIcon {
                                id: appsRowIcon
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.dp(56)
                                height: width
                                radius: MRadius.lg
                                source: root.safeImageUrl(modelData.icon || "")
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - appsRowIcon.width - appsRowAction.width - parent.spacing * 2
                                spacing: root.dp(2)
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
                                id: appsRowAction
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
                            anchors.leftMargin: MSpacing.md + root.dp(56 + 14)
                            anchors.right: parent.right
                            anchors.rightMargin: MSpacing.md
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
                    width: parent.width - MSpacing.xxl
                    // Mirrors the ListView's own `visible: model.length > 0`
                    // above, so the list and its empty state can never both
                    // be hidden -- the split-predicate shape that left
                    // Discover rendering a void with nothing to explain it.
                    visible: !appsList.visible && !root.catalogLoading
                    iconName: "grid"
                    iconSize: root.dp(64)
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
                    anchors.topMargin: root.dp(8)
                    clip: true
                    spacing: 0
                    visible: root.installedApps.length > 0
                    model: root.installedApps

                    delegate: Item {
                        width: ListView.view.width
                        height: root.dp(68)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: MSpacing.md
                            anchors.rightMargin: MSpacing.md
                            spacing: root.dp(14)

                            AppIcon {
                                id: installedRowIcon
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.dp(48)
                                height: width
                                radius: MRadius.lg
                                // marathon-store-refresh-state emits
                                // file:// URLs to PNGs in
                                // ~/.local/share/flatpak/exports/share/icons/…
                                // Local paths bypass the SSRF clamp
                                // because they were written by the
                                // shell-handler script.
                                source: modelData.icon || ""
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - installedRowIcon.width - parent.spacing
                                spacing: root.dp(2)
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
                            anchors.leftMargin: MSpacing.md + root.dp(48 + 14)
                            anchors.right: parent.right
                            anchors.rightMargin: MSpacing.md
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
                    width: parent.width - MSpacing.xxl
                    visible: root.installedApps.length === 0
                    iconName: "download"
                    iconSize: root.dp(64)
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
                    width: parent.width - MSpacing.xxl
                    iconName: "user"
                    iconSize: root.dp(64)
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
                        id: detailTopBar
                        width: parent.width
                        title: displayApp ? (displayApp.name || appId) : appId
                    }

                    Flickable {
                        width: parent.width
                        height: parent.height - detailTopBar.height
                        clip: true
                        contentHeight: detailCol.height + MSpacing.lg

                        Column {
                            id: detailCol
                            width: parent.width
                            topPadding: MSpacing.md
                            spacing: MSpacing.md

                            Row {
                                x: MSpacing.md
                                width: parent.width - MSpacing.md * 2
                                spacing: root.dp(14)

                                AppIcon {
                                    id: detailIcon
                                    width: root.dp(88)
                                    height: width
                                    radius: MRadius.xl
                                    source: displayApp ? root.safeImageUrl(displayApp.icon || "") : ""
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - detailIcon.width - parent.spacing
                                    spacing: root.dp(4)
                                    Text {
                                        width: parent.width
                                        text: displayApp ? (displayApp.developer_name || displayApp.author || "") : ""
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        elide: Text.ElideRight
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
                                x: MSpacing.md
                                width: parent.width - MSpacing.md * 2
                                text: displayApp ? (displayApp.summary || "") : ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeHeadline
                                font.weight: Font.Medium
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                x: MSpacing.md
                                width: parent.width - MSpacing.md * 2
                                text: displayApp ? (displayApp.description || "").replace(/<[^>]+>/g, "") : ""
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}
