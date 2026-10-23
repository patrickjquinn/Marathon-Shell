pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Qt.labs.folderlistmodel

// Marathon Store's data layer: a Flathub catalogue with ODRS ratings and
// reviews. The pages reach everything here through `store`.
// Catalogue data comes from flathub.org's v2 API, ratings and reviews from
// the Open Desktop Ratings Service that GNOME Software and Discover use.
// Installs go through the marathon-store:// URL scheme to a shell-side
// handler that runs flatpak and writes per-app progress files to
// $XDG_RUNTIME_DIR, which this file polls.
QtObject {
    id: root

    // Tests point these at a dead host and a fixture directory.
    property string flathubApi: "https://flathub.org/api/v2"
    property string odrsApi: "https://odrs.gnome.org/1.0/reviews/api"
    // Same directory the store handler scripts write to ($XDG_RUNTIME_DIR).
    property string stateDir: String(StandardPaths.writableLocation(StandardPaths.RuntimeLocation)).replace("file://", "") + "/marathon-store-state"
    property var openExternally: url => Qt.openUrlExternally(url)
    property url cacheFile: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/catalog.ini"
    // How long a request may go unanswered by the handler, in seconds.
    property int helperTimeout: 30

    property var collections: ({})
    property var appOfTheDay: null
    property var appstreamCache: ({})
    property var summaryCache: ({})
    property var installedApps: []
    // Only apps made for phones in lists and search, as the shell's
    // filterMobileFriendlyApps says (StoreApp binds it); installed apps and
    // an app's own page are always shown.
    property bool phoneOnly: true
    // The handler's settings.json and phone-apps.json (id → true).
    property var storeSettings: defaultSettings
    readonly property var defaultSettings: ({
            "flathub": true,
            "fdroid": true,
            "antiFeatures": true,
            "autoUpdate": true,
            "updateOnMetered": false
        })
    property var phoneApps: ({})
    // This phone's Android (the handler's android-device.json): features,
    // libraries, abis, sdk, gms; null until Android has answered once.
    property var androidDevice: null
    property var pendingUpdates: []
    property bool stateRefreshInFlight: false
    property int stateRefreshStartedAt: 0
    property bool installedStateFresh: false
    property bool updateStateFresh: false
    // appId → the handler's last progress record: {state, percent, error}.
    property var jobs: ({})
    // Four collections load concurrently, so this counts fetches in flight
    // rather than being a bool that the first response would clear.
    property int catalogFetchesInFlight: 0
    readonly property bool catalogLoading: catalogFetchesInFlight > 0 || startupTimer.running
    property string lastError: ""
    // When the catalogue on screen was saved, if it came from the cache and
    // nothing fresher has loaded since; 0 otherwise.
    property real catalogSavedAt: 0
    // Collections can come back with keys but no entries once the aarch64
    // filter has run, so "loaded" means apps were counted, not keys.
    readonly property int catalogAppCount: {
        let n = 0;
        for (const k in collections)
            n += (collections[k] || []).length;
        return n;
    }
    // The first install, update or removal still running, for the cover.
    readonly property string activeJobId: {
        const ids = Object.keys(jobs);
        for (let i = 0; i < ids.length; i++) {
            if (jobRunning(jobs[ids[i]]))
                return ids[i];
        }
        return "";
    }
    // appId → the verb its running job was started with.
    property var _verbs: ({})

    // Flathub's main categories, in the order its own site lists them.
    readonly property var categories: [
        {
            "id": "audiovideo",
            "label": qsTr("Audio & Video"),
            "icon": "music"
        },
        {
            "id": "development",
            "label": qsTr("Developer Tools"),
            "icon": "developer-mode"
        },
        {
            "id": "education",
            "label": qsTr("Education"),
            "icon": "education"
        },
        {
            "id": "game",
            "label": qsTr("Games"),
            "icon": "game"
        },
        {
            "id": "graphics",
            "label": qsTr("Graphics & Photo"),
            "icon": "graphics"
        },
        {
            "id": "healthfitness",
            "label": qsTr("Health & Fitness"),
            "icon": "health"
        },
        {
            "id": "network",
            "label": qsTr("Internet"),
            "icon": "browser"
        },
        {
            "id": "office",
            "label": qsTr("Productivity"),
            "icon": "office"
        },
        {
            "id": "science",
            "label": qsTr("Science"),
            "icon": "science"
        },
        {
            "id": "system",
            "label": qsTr("System"),
            "icon": "settings"
        },
        {
            "id": "utility",
            "label": qsTr("Utilities"),
            "icon": "utility"
        }
    ]

    readonly property var heroApp: appOfTheDay && shown([appOfTheDay]).length > 0 ? appOfTheDay : firstOf(["verified", "popular", "trending"])
    readonly property var trendingApps: take(shown(collections["trending"]), [heroApp], 3)
    readonly property var mobileApps: take(shown(collections["mobile"]), [heroApp].concat(trendingApps), 5)
    readonly property var newApps: take(shown(collections["recently-added"]), [heroApp].concat(trendingApps, mobileApps), 5)
    readonly property var topApps: take(shown(collections["popular"]), [], 24)
    readonly property var updateApps: pendingUpdates.map(u => installedEntry(u.app_id) || u)
    readonly property bool showingSavedCatalog: catalogSavedAt > 0 && !catalogLoading

    signal pushRequested(url page, var properties)
    // A job left the running states: done, removed or failed.
    signal jobFinished(string appId, string verb, var job)

    // ── Lists ─────────────────────────────────────────────────

    function idOf(app) {
        return app ? (app.app_id || app.id || "") : "";
    }

    function firstOf(names) {
        for (let i = 0; i < names.length; i++) {
            const list = shown(collections[names[i]]);
            if (list && list.length > 0)
                return list[0];
        }
        return null;
    }

    // Up to `count` entries of `list` that are not already in `shown`, so
    // Discover never lists the same app twice.
    function take(list, shown, count) {
        const skip = shown.map(idOf);
        const out = [];
        for (let i = 0; list && i < list.length && out.length < count; i++) {
            const id = idOf(list[i]);
            if (id && skip.indexOf(id) < 0)
                out.push(list[i]);
        }
        return out;
    }

    // Flathub's own flag is the AppStream rule the handler applies to the
    // whole catalogue (phone-apps.json), so a list works before the
    // handler's index exists.
    function fitsPhone(app) {
        const id = idOf(app);
        return isAndroid(id) || phoneApps[id] === true || (app && (app.isMobileFriendly === true || relationsFit(app)));
    }

    // The handler's rule (crates/marathon-store-handler/src/phone.rs) on an
    // /appstream entry's requires, recommends and supports: no required
    // length rules out a 360 px side, and one admits it, with touch.
    function relationsFit(app) {
        const admits = r => {
            if (r.type !== "display_length" || r.side === "longest" || !/^[0-9]+$/.test(String(r.value)))
                return null;
            const px = parseInt(r.value, 10);
            const compare = r.compare || "ge";
            return compare === "ge" ? px <= 360 : compare === "gt" ? px < 360 : compare === "le" ? px >= 768 : compare === "lt" ? px > 768 : false;
        };
        let fits = false, touch = false;
        for (const kind of ["requires", "recommends", "supports"]) {
            for (const r of (app[kind] || [])) {
                const a = admits(r);
                if (a === false && kind === "requires")
                    return false;
                fits = fits || a === true;
                touch = touch || (r.type === "control" && r.value === "touch");
            }
        }
        return fits && touch;
    }

    // Whether the person's sources and F-Droid choice let the app be listed.
    function offered(app) {
        if (!isAndroid(idOf(app)))
            return storeSettings.flathub !== false;
        return storeSettings.fdroid !== false && (storeSettings.antiFeatures !== false || (app.antiFeatures || []).length === 0);
    }

    function shown(list, all) {
        return (list || []).filter(a => offered(a) && (all || !phoneOnly || fitsPhone(a)));
    }

    // The offered apps the phone filter leaves out of `list`.
    function hiddenCount(list) {
        return phoneOnly ? shown(list, true).length - shown(list).length : 0;
    }

    function loadStoreSettings() {
        readLocalJson(stateDir + "/settings.json", function (data) {
            root.storeSettings = Object.assign({}, root.defaultSettings, data || {});
        });
        readLocalJson(stateDir + "/android-device.json", function (data) {
            if (data && data.abis)
                root.androidDevice = data;
        });
        readLocalJson(stateDir + "/phone-apps.json", function (data) {
            const set = {};
            ((data && data.apps) || []).forEach(id => set[id] = true);
            root.phoneApps = set;
        });
    }

    function pickAarch64(hits) {
        return hits.filter(a => a.arches && a.arches.indexOf("aarch64") >= 0);
    }

    // ── HTTP ──────────────────────────────────────────────────
    //
    // Every fetch is pinned to Flathub's API or ODRS, and every Image source
    // is clamped to Flathub's hosts, so a poisoned response can't steer the
    // Store at a LAN host or a file:// URL through crafted icon or
    // screenshot links.

    function isAllowedUrl(u) {
        return typeof u === "string" && (u.indexOf(flathubApi + "/") === 0 || u.indexOf(odrsApi + "/") === 0);
    }

    function safeImageUrl(u) {
        if (typeof u !== "string")
            return "";
        if (u.indexOf("https://dl.flathub.org/") === 0 || u.indexOf("https://flathub.org/") === 0 || u.indexOf("https://f-droid.org/repo/") === 0)
            return u;
        return "";
    }

    // Installed entries carry no network icon, and their exported one sits in
    // the real home, which this app's sandbox can't read; they borrow the
    // Flathub icon from the appstream record, fetched by ensureIcon().
    function iconFor(app) {
        const _ = root._iconTick;
        if (app && app.icon)
            return safeImageUrl(app.icon);
        if (isAndroid(idOf(app))) {
            const listed = androidApp(idOf(app));
            return listed ? safeImageUrl(listed.icon) : "";
        }
        const full = appstreamCache[idOf(app)];
        return full ? safeImageUrl(full.icon || "") : "";
    }

    property int _iconTick: 0

    function ensureIcon(app) {
        const id = idOf(app);
        if (!id || isAndroid(id) || (app && app.icon) || appstreamCache[id])
            return;
        loadAppstream(id, function () {
            root._iconTick += 1;
        });
    }

    function fetchJson(url, body, cb) {
        if (!root.isAllowedUrl(url)) {
            cb(null, "refusing url outside Flathub and ODRS");
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

    // ── Catalogue ─────────────────────────────────────────────

    function loadCatalog() {
        lastError = "";
        if (catalogAppCount === 0)
            restoreCatalog();
        loadInstalled();
        loadUpdates();
        startupTimer.queue = [() => refreshState(), () => loadAppOfTheDay(), () => loadCollection("verified"), () => loadCollection("trending"), () => loadCollection("popular"), () => loadCollection("mobile"), () => loadCollection("recently-added")];
        startupTimer.running = true;
        androidCatalogTimer.restart();
    }

    function loadCollection(name) {
        catalogFetchesInFlight += 1;
        fetchJson(flathubApi + "/collection/" + name + "?page=1&per_page=" + (phoneOnly ? 60 : 30) + "&locale=en", null, function (data, err) {
            root.catalogFetchesInFlight -= 1;
            if (err) {
                root.lastError = name + ": " + err;
                return;
            }
            var next = Object.assign({}, root.collections);
            next[name] = pickAarch64(data.hits || []);
            root.collections = next;
            root.lastError = "";
            root.catalogSavedAt = 0;
            root.saveCatalog();
        });
    }

    function loadAppOfTheDay() {
        fetchJson(flathubApi + "/app-picks/app-of-the-day/" + todayUtc(), null, function (data, err) {
            if (err || !data || !data.app_id)
                return;
            loadAppstream(data.app_id, function (full) {
                if (!full)
                    return;
                root.appOfTheDay = full;
                root.saveCatalog();
            });
        });
    }

    function todayUtc() {
        return new Date().toISOString().slice(0, 10);
    }

    function loadAppstream(appId, cb) {
        if (appstreamCache[appId]) {
            cb(appstreamCache[appId]);
            return;
        }
        fetchJson(flathubApi + "/appstream/" + appId, null, function (full, err) {
            if (err || !full) {
                cb(null);
                return;
            }
            var next = Object.assign({}, root.appstreamCache);
            next[appId] = full;
            root.appstreamCache = next;
            cb(full);
        });
    }

    // Sizes and sandbox permissions from /summary, with last month's
    // installs from /stats folded in.
    function loadSummary(appId, cb) {
        if (summaryCache[appId]) {
            cb(summaryCache[appId]);
            return;
        }
        fetchJson(flathubApi + "/summary/" + appId, null, function (summary, err) {
            if (err || !summary) {
                cb(null);
                return;
            }
            fetchJson(flathubApi + "/stats/" + appId, null, function (stats) {
                summary.installs_last_month = stats ? stats.installs_last_month : undefined;
                var next = Object.assign({}, root.summaryCache);
                next[appId] = summary;
                root.summaryCache = next;
                cb(summary);
            });
        });
    }

    // A whole Flathub collection for a list page, e.g.
    // "collection/category/game" or "collection/mobile".
    // Offline, the last copy of the list comes back with the error and the
    // time it was saved.
    function loadList(source, cb) {
        fetchJson(flathubApi + "/" + source + "?page=1&per_page=60&locale=en", null, function (data, err) {
            if (err) {
                const saved = root.savedJson("list/" + source);
                cb(saved ? saved.apps : [], err, saved ? saved.ts : 0);
                return;
            }
            const list = pickAarch64(data.hits || []);
            root.saveJson("list/" + source, {
                "ts": Math.floor(Date.now() / 1000),
                "apps": list.map(root.slim)
            });
            cb(list, "", 0);
        });
    }

    // ── Offline cache ─────────────────────────────────────────
    //
    // The last catalogue and lists, so a launch without a network still has
    // something to browse. Hits are cut down to the fields the lists show.

    readonly property var _slimKeys: ["app_id", "id", "name", "summary", "icon", "developer_name", "main_categories", "categories", "installs_last_month", "verification_verified", "version", "isMobileFriendly"]

    function slim(app) {
        const out = {};
        _slimKeys.forEach(k => {
            if (app[k] !== undefined)
                out[k] = app[k];
        });
        return out;
    }

    function savedJson(key) {
        try {
            const raw = _cache.value(key, "");
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }

    function saveJson(key, value) {
        _cache.setValue(key, JSON.stringify(value));
        _cache.sync();
    }

    function saveCatalog() {
        catalogSaveTimer.restart();
    }

    function writeCatalog() {
        const slimmed = {};
        for (const k in collections)
            slimmed[k] = collections[k].map(slim);
        saveJson("catalog", {
            "ts": Math.floor(Date.now() / 1000),
            "collections": slimmed,
            "appOfTheDay": appOfTheDay
        });
    }

    function restoreCatalog() {
        const saved = savedJson("catalog");
        if (!saved || !saved.collections)
            return;
        collections = saved.collections;
        if (saved.appOfTheDay)
            appOfTheDay = saved.appOfTheDay;
        catalogSavedAt = saved.ts || 0;
    }

    function searchApps(query, cb) {
        const body = {
            "query": query,
            "filters": [
                {
                    "filterType": "arches",
                    "value": "aarch64"
                }
            ],
            "hits_per_page": 40
        };
        const android = searchAndroid(query, 20).filter(a => offered(a));
        if (storeSettings.flathub === false) {
            cb(android, "");
            return;
        }
        fetchJson(flathubApi + "/search", body, function (data, err) {
            const hits = err ? [] : (data.hits || []);
            cb(hits.concat(android), err && android.length === 0 ? err : "");
        });
    }

    function installsFor(app, summary) {
        const n = (app && app.installs_last_month) || (summary && summary.installs_last_month);
        return n > 0 ? n : 0;
    }

    function isVerified(app) {
        return !!app && (app.verification_verified === true || (app.metadata !== undefined && app.metadata["flathub::verification::verified"] === "true"));
    }

    // ── Categories ────────────────────────────────────────────
    //
    // Collection hits don't carry categories, so the appstream record is
    // fetched per tile; _categoryTick re-renders tiles as each one lands.

    property int _categoryTick: 0
    property var _categoryFor: ({})

    function categoryName(raw) {
        const key = String(raw).toLowerCase();
        for (let i = 0; i < categories.length; i++) {
            if (categories[i].id === key)
                return categories[i].label;
        }
        return raw;
    }

    // Pure: reads the cache, never writes it, so bindings may call it.
    function categoryLabel(app) {
        const _ = root._categoryTick;
        const id = idOf(app);
        if (_categoryFor[id])
            return _categoryFor[id];
        // A plain string in collection and search hits, a list elsewhere.
        if (app && app.main_categories)
            return categoryName([].concat(app.main_categories)[0]);
        if (app && app.categories && app.categories.length > 0)
            return categoryName(app.categories[0]);
        return qsTr("App");
    }

    function ensureCategory(app) {
        const id = idOf(app);
        if (!id || _categoryFor[id] || (app.categories && app.categories.length > 0) || app.main_categories)
            return;
        loadAppstream(id, function (full) {
            if (!full || !full.categories || full.categories.length === 0)
                return;
            var next = Object.assign({}, root._categoryFor);
            next[id] = categoryName(full.categories[0]);
            root._categoryFor = next;
            root._categoryTick += 1;
        });
    }

    // ── Ratings & reviews (ODRS) ──────────────────────────────

    property int _ratingTick: 0
    property var _ratings: ({})

    // Pure: {average, total, counts} once loaded and rated, otherwise null.
    function ratingFor(appId) {
        const _ = root._ratingTick;
        const r = _ratings[appId];
        return r && r.total > 0 ? r : null;
    }

    function ensureRating(appId) {
        if (!appId || isAndroid(appId) || _ratings[appId] !== undefined)
            return;
        const next = Object.assign({}, _ratings);
        next[appId] = null;
        _ratings = next;
        // ODRS keys some apps by their .desktop id rather than the
        // Flathub id, so try both.
        fetchRating(appId, function (r) {
            if (r && r.total > 0)
                storeRating(appId, r);
            else
                fetchRating(appId + ".desktop", function (r2) {
                    storeRating(appId, r2);
                });
        });
    }

    function fetchRating(key, cb) {
        fetchJson(odrsApi + "/ratings/" + key, null, function (d, err) {
            if (err || !d || !d.total) {
                cb(null);
                return;
            }
            var counts = {
                "1": d.star1 || 0,
                "2": d.star2 || 0,
                "3": d.star3 || 0,
                "4": d.star4 || 0,
                "5": d.star5 || 0
            };
            var total = counts[1] + counts[2] + counts[3] + counts[4] + counts[5];
            var sum = counts[1] + counts[2] * 2 + counts[3] * 3 + counts[4] * 4 + counts[5] * 5;
            cb(total > 0 ? {
                "average": sum / total,
                "total": total,
                "counts": counts
            } : null);
        });
    }

    function storeRating(appId, r) {
        const next = Object.assign({}, _ratings);
        next[appId] = r || {
            "total": 0
        };
        _ratings = next;
        _ratingTick += 1;
    }

    // The most helpful written reviews first.
    function loadReviews(appId, cb) {
        // ODRS wants a 40-hex user_hash to mark the caller's own reviews;
        // reading anonymously, any stable value does.
        const body = {
            "app_id": appId,
            "locale": "en_GB",
            "distro": "postmarketOS",
            "version": "unknown",
            "user_hash": Qt.md5("marathon-store") + "00000000",
            "limit": 20,
            "compat_ids": [appId + ".desktop"]
        };
        fetchJson(odrsApi + "/fetch", body, function (list, err) {
            if (err || !Array.isArray(list)) {
                cb([]);
                return;
            }
            var written = list.filter(r => r.description && !r.reported);
            written.sort((a, b) => (b.score || 0) - (a.score || 0));
            cb(written.slice(0, 3));
        });
    }

    // ── Formatting ────────────────────────────────────────────

    function formatCount(n) {
        if (!(n > 0))
            return "–";
        if (n >= 1000000)
            return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "k";
        return String(n);
    }

    function formatSize(bytes) {
        if (!(bytes > 0))
            return "–";
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(1) + " GB";
        if (bytes >= 1048576)
            return (bytes / 1048576).toFixed(bytes >= 104857600 ? 0 : 1) + " MB";
        return Math.max(1, Math.round(bytes / 1024)) + " KB";
    }

    function timeAgo(seconds) {
        const days = Math.floor((Date.now() / 1000 - seconds) / 86400);
        if (!(seconds > 0) || days < 0)
            return "";
        if (days < 1)
            return qsTr("today");
        if (days < 2)
            return qsTr("yesterday");
        if (days < 30)
            return qsTr("%1 days ago").arg(days);
        if (days < 365)
            return days < 60 ? qsTr("1 month ago") : qsTr("%1 months ago").arg(Math.floor(days / 30));
        return days < 730 ? qsTr("1 year ago") : qsTr("%1 years ago").arg(Math.floor(days / 365));
    }

    function releaseLine(release) {
        const when = timeAgo(Number(release.timestamp));
        return qsTr("Version %1").arg(release.version) + (when !== "" ? " · " + when : "");
    }

    function reviewByline(review) {
        const when = timeAgo(Number(review.date_created));
        return (review.user_display || qsTr("Anonymous")) + (when !== "" ? " · " + when : "");
    }

    // Appstream text is <p>/<ul>/<li> markup carrying the source XML's
    // indentation, which StyledText would render literally. <img> goes
    // first: StyledText fetches it, bypassing the safeImageUrl clamp.
    function cleanMarkup(html) {
        return String(html).replace(/<img[^>]*>/gi, "").replace(/\s+/g, " ").trim();
    }

    // The smallest size at least `targetHeight` tall, else the largest.
    function pickScreenshot(shot, targetHeight) {
        const sizes = (shot.sizes || []).map(s => ({
                    "src": s.src,
                    "width": Number(s.width),
                    "height": Number(s.height)
                })).filter(s => s.width > 0 && s.height > 0).sort((a, b) => a.height - b.height);
        if (sizes.length === 0)
            return null;
        for (let i = 0; i < sizes.length; i++) {
            if (sizes[i].height >= targetHeight)
                return sizes[i];
        }
        return sizes[sizes.length - 1];
    }

    // Flatpak sandbox holes in plain words. Ordinary needs (GPU, Wayland,
    // the app's own data) are left out so the list stays meaningful.
    function describePermissions(p) {
        if (!p)
            return [];
        const out = [];
        const has = (list, v) => !!list && list.indexOf(v) >= 0;
        if (has(p.shared, "network"))
            out.push({
                "icon": "world",
                "label": qsTr("Internet"),
                "detail": qsTr("Can connect to the network")
            });
        const fs = p.filesystems || [];
        const broad = fs.filter(f => /^(host|home|host-os|host-etc)(:rw)?$/.test(f));
        if (broad.length > 0)
            out.push({
                "icon": "file-folder",
                "label": qsTr("All your files"),
                "detail": qsTr("Can read and change files outside its sandbox"),
                "risky": true
            });
        // gvfs is GNOME's virtual-filesystem plumbing, not a user folder.
        const named = fs.filter(f => !/^xdg-run\/gvfs/.test(f));
        if (broad.length === 0 && named.length > 0)
            out.push({
                "icon": "folder",
                "label": qsTr("Some folders"),
                "detail": named.map(f => f.replace(/^xdg-/, "").replace(/:(ro|rw|create)$/, "")).join(", ")
            });
        if (has(p.devices, "all"))
            out.push({
                "icon": "usb",
                "label": qsTr("All devices"),
                "detail": qsTr("Camera, USB and other hardware"),
                "risky": true
            });
        if (has(p.sockets, "pulseaudio"))
            out.push({
                "icon": "speaker",
                "label": qsTr("Audio"),
                "detail": qsTr("Can play and record sound")
            });
        if (has(p.sockets, "x11") && !has(p.sockets, "wayland"))
            out.push({
                "icon": "display",
                "label": qsTr("Legacy display access"),
                "detail": qsTr("Uses X11, which isolates apps from each other less well"),
                "risky": true
            });
        if (has(p.sockets, "cups"))
            out.push({
                "icon": "print",
                "label": qsTr("Printing"),
                "detail": qsTr("Can send documents to printers")
            });
        if (has(p.features, "bluetooth") || has(p.devices, "bluetooth"))
            out.push({
                "icon": "bluetooth",
                "label": qsTr("Bluetooth"),
                "detail": qsTr("Can talk to Bluetooth devices")
            });
        return out;
    }

    function infoRows(app, summary) {
        const rows = [];
        var add = (label, value) => {
            if (value)
                rows.push({
                    "label": label,
                    "value": value
                });
        };
        const release = app.releases && app.releases.length > 0 ? app.releases[0] : null;
        add(qsTr("Developer"), app.developer_name);
        add(qsTr("Version"), release ? release.version : "");
        add(qsTr("Updated"), release ? timeAgo(Number(release.timestamp)) : "");
        add(qsTr("Installed size"), summary ? formatSize(summary.installed_size) : "");
        add(qsTr("License"), app.project_license);
        return rows;
    }

    // ── Installs ──────────────────────────────────────────────

    function installedEntry(appId) {
        for (let i = 0; i < installedApps.length; i++) {
            if (installedApps[i].app_id === appId)
                return installedApps[i];
        }
        return null;
    }

    readonly property string helperSilentError: qsTr("The Store helper didn't respond. Try again.")

    // The handler records flatpak's last error line; turn the common ones
    // into something a phone user can act on.
    function jobError(job) {
        const raw = job && job.error ? job.error : "";
        if (raw === helperSilentError)
            return raw;
        if (/No space left|min-free-space/i.test(raw))
            return qsTr("Not enough storage space on this phone.");
        if (/Could not resolve|Network|Couldn.t connect|timed out/i.test(raw))
            return qsTr("Couldn't reach Flathub. Check your connection and try again.");
        if (/No remote refs|Nothing matches|not found in remote|No such ref|remote .* not found/i.test(raw))
            return qsTr("Flathub doesn't have this app for this phone any more.");
        if (/already installed/i.test(raw))
            return qsTr("It's already installed. Pull down on Installed to refresh.");
        if (/Permission denied|Not authorized|not allowed/i.test(raw))
            return qsTr("The Store wasn't allowed to make this change.");
        if (/GPG|signature|checksum/i.test(raw))
            return qsTr("The download couldn't be verified. Try again later.");
        if (raw !== "")
            console.warn("Store: unrecognised flatpak error:", raw);
        return qsTr("Couldn't finish. Try again later.");
    }

    function jobFor(appId) {
        return jobs[appId] || null;
    }

    // A finished job answers before installed.json catches up, so the
    // button flips the moment flatpak returns.
    function isInstalled(appId) {
        const job = jobs[appId];
        if (job && job.state === "done")
            return true;
        if (job && job.state === "removed")
            return false;
        return installedEntry(appId) !== null;
    }

    // An Android app without a launcher activity (a keyboard, a plugin) has
    // nothing to open. One installed a moment ago and not listed yet gets
    // Open until the list says otherwise.
    function canOpen(appId) {
        if (!isAndroid(appId))
            return true;
        const entry = installedEntry(appId);
        return entry === null || entry.launchable !== false;
    }

    function hasUpdate(appId) {
        const job = jobs[appId];
        if (job && job.state === "done")
            return false;
        return pendingUpdates.some(u => u.app_id === appId);
    }

    function isValidRef(appId) {
        if (typeof appId !== "string" || appId.indexOf("..") >= 0)
            return false;
        if (isAndroid(appId))
            return /^android:[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/.test(appId);
        return /^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$/.test(appId);
    }

    function startJob(verb, appId) {
        if (!isValidRef(appId))
            return;
        const next = Object.assign({}, jobs);
        next[appId] = {
            "appId": appId,
            "state": verb === "uninstall" ? "removing" : "pending",
            "percent": -1,
            "error": "",
            "ts": Math.floor(Date.now() / 1000)
        };
        jobs = next;
        _setVerb(appId, verb);
        jobPollTimer.running = true;
        // The name is for the job's row in the Hub.
        const name = verb === "uninstall" ? "" : "?name=" + encodeURIComponent(nameOf(appId));
        root.openExternally("marathon-store://" + verb + "/" + appId + name);
    }

    function installApp(appId) {
        startJob("install", appId);
    }

    function updateApp(appId) {
        startJob("update", appId);
    }

    function uninstallApp(appId) {
        startJob("uninstall", appId);
    }

    function canCancel(job) {
        return !!job && (job.state === "pending" || job.state === "installing");
    }

    // The job stays running as "cancelling" until the handler reports back.
    function cancelJob(appId) {
        const job = jobs[appId];
        if (!isValidRef(appId) || !canCancel(job))
            return;
        const next = Object.assign({}, jobs);
        next[appId] = Object.assign({}, job, {
            "state": "cancelling",
            "cancelTs": Math.floor(Date.now() / 1000)
        });
        jobs = next;
        jobPollTimer.running = true;
        root.openExternally("marathon-store://cancel/" + appId);
    }

    function updateAll() {
        for (let i = 0; i < pendingUpdates.length; i++) {
            const next = Object.assign({}, jobs);
            next[pendingUpdates[i].app_id] = {
                "appId": pendingUpdates[i].app_id,
                "state": "pending",
                "percent": -1,
                "error": "",
                "ts": Math.floor(Date.now() / 1000)
            };
            jobs = next;
            _setVerb(pendingUpdates[i].app_id, "update");
        }
        jobPollTimer.running = true;
        root.openExternally("marathon-store://update-all/x");
    }

    function _setVerb(appId, verb) {
        const next = Object.assign({}, _verbs);
        next[appId] = verb;
        _verbs = next;
    }

    function openApp(appId) {
        if (isAndroid(appId) && isValidRef(appId))
            root.openExternally("marathon-store://open/waydroid." + appId.substring(8));
        else if (isValidRef(appId))
            root.openExternally("marathon-store://open/" + appId);
    }

    function jobRunning(job) {
        return job.state === "pending" || job.state === "installing" || job.state === "removing" || job.state === "cancelling";
    }

    function _finish(appId, data) {
        var next = Object.assign({}, jobs);
        next[appId] = data;
        jobs = next;
        stateRefreshTimer.restart();
        jobFinished(appId, _verbs[appId] || "install", data);
    }

    function pollJobs() {
        const ids = Object.keys(jobs).filter(id => jobRunning(jobs[id]));
        if (ids.length === 0) {
            jobPollTimer.running = false;
            return;
        }
        ids.forEach(function (appId) {
            readLocalJson(stateDir + "/install-progress-" + appId + ".json", function (data) {
                const current = root.jobs[appId];
                if (!current || !root.jobRunning(current))
                    return;
                const now = Math.floor(Date.now() / 1000);
                const asked = current.cancelTs || current.ts;
                // A record older than the job is the previous run's result.
                if (!data || data.ts < current.ts) {
                    if (now - asked > root.helperTimeout)
                        root._finish(appId, {
                            "appId": appId,
                            "state": "failed",
                            "percent": -1,
                            "error": root.helperSilentError,
                            "ts": now
                        });
                    return;
                }
                // Progress written before the stop landed; hold "cancelling"
                // unless the handler never answers the cancel.
                if (current.state === "cancelling" && root.jobRunning(data) && now - asked <= root.helperTimeout)
                    return;
                if (!root.jobRunning(data)) {
                    root._finish(appId, data);
                    return;
                }
                var next = Object.assign({}, root.jobs);
                next[appId] = data;
                root.jobs = next;
            });
        });
    }

    function loadInstalled() {
        readLocalJson(stateDir + "/installed.json", function (data) {
            if (!data || !Array.isArray(data.installed))
                return;
            var list = data.installed;
            root.installedApps = list.map(a => ({
                        "app_id": a.app_id,
                        "name": a.name,
                        "version": a.version,
                        "launchable": a.launchable !== false
                    }));
            if (data.ts >= root.stateRefreshStartedAt)
                root.installedStateFresh = true;
        });
    }

    function loadUpdates() {
        readLocalJson(stateDir + "/updates.json", function (data) {
            if (!data || !Array.isArray(data.updates))
                return;
            root.pendingUpdates = data.updates;
            if (data.ts >= root.stateRefreshStartedAt)
                root.updateStateFresh = true;
        });
    }

    // A reopened Store picks up the installs still running from the handler's
    // progress records; a record untouched for half an hour is a dead run.
    function adoptJobs() {
        const now = Math.floor(Date.now() / 1000);
        for (let i = 0; i < _progressFiles.count; i++) {
            const appId = String(_progressFiles.get(i, "fileName")).replace(/^install-progress-/, "").replace(/\.json$/, "");
            if (!isValidRef(appId) || jobs[appId])
                continue;
            readLocalJson(stateDir + "/install-progress-" + appId + ".json", function (data) {
                if (!data || !root.jobRunning(data) || now - data.ts > 1800 || root.jobs[appId])
                    return;
                var next = Object.assign({}, root.jobs);
                next[appId] = data;
                root.jobs = next;
                root._setVerb(appId, data.verb || (data.state === "removing" ? "uninstall" : "install"));
                jobPollTimer.running = true;
            });
        }
    }

    function refreshState() {
        if (stateRefreshInFlight)
            return;
        stateRefreshInFlight = true;
        stateRefreshStartedAt = Math.floor(Date.now() / 1000);
        installedStateFresh = false;
        updateStateFresh = false;
        adoptJobs();
        loadInstalled();
        loadUpdates();
        loadStoreSettings();
        root.openExternally("marathon-store://refresh-state/all");
        stateRefreshTimer.tries = 0;
        stateRefreshTimer.restart();
    }

    // ── Navigation ────────────────────────────────────────────

    function nameOf(appId) {
        const listed = isAndroid(appId) ? androidApp(appId) : null;
        if (listed)
            return listed.name;
        const full = appstreamCache[appId];
        const entry = installedEntry(appId);
        return (full && full.name) || (entry && entry.name) || _apkNames[appId] || appId;
    }

    function openDetail(app) {
        if (isAndroid(idOf(app))) {
            pushRequested(Qt.resolvedUrl("../pages/AndroidAppPage.qml"), {
                "store": root,
                "app": androidApp(idOf(app)) || app
            });
            return;
        }
        pushRequested(Qt.resolvedUrl("../pages/AppDetailPage.qml"), {
            "store": root,
            "appId": idOf(app),
            "summaryApp": app
        });
    }

    function openCategory(id, label) {
        openList(label, "collection/category/" + id);
    }

    function openCollection(name, label) {
        openList(label, "collection/" + name);
    }

    function openList(title, source) {
        pushRequested(Qt.resolvedUrl("../pages/AppListPage.qml"), {
            "store": root,
            "title": title,
            "source": source
        });
    }

    function openScreenshots(shots, index) {
        pushRequested(Qt.resolvedUrl("../pages/ScreenshotViewer.qml"), {
            "store": root,
            "screenshots": shots,
            "startIndex": index
        });
    }

    // ── Android apps: F-Droid's catalogue, installed through Deckard ──
    //
    // The handler verifies F-Droid's signed index, keeps a compact catalogue
    // and copies it to stateDir/fdroid.json; installs and removals go
    // through deckardd, so Android's own installer never shows.

    property var androidApps: []
    property var _androidById: ({})
    property real androidSyncedAt: 0
    // An .apk's confirmation: the handler's apk-inspect.json for the file.
    property var apkInfo: null
    // An .apk's label from its confirmation page, for the notices.
    property var _apkNames: ({})

    function isAndroid(appId) {
        return typeof appId === "string" && appId.indexOf("android:") === 0;
    }

    function androidApp(appId) {
        return _androidById[appId] || null;
    }

    // Loads the copy in stateDir; asks for a sync when it is missing or a
    // day old (the handler skips it on a metered network or a low battery).
    function loadAndroidCatalog(syncIfStale) {
        readLocalJson(stateDir + "/fdroid.json", function (data) {
            if (data && data.apps) {
                const byId = {};
                data.apps.forEach(a => byId[a.app_id] = a);
                root._androidById = byId;
                root.androidApps = data.apps;
                root.androidSyncedAt = data.ts || 0;
            }
            if (syncIfStale && root.storeSettings.fdroid !== false && Date.now() / 1000 - root.androidSyncedAt > 86400) {
                root.openExternally("marathon-store://fdroid-sync/all");
                androidSyncPoll.tries = 0;
                androidSyncPoll.running = true;
            }
        });
    }

    function searchAndroid(query, limit) {
        const q = String(query || "").toLowerCase();
        if (q.length === 0)
            return [];
        const out = [];
        for (let i = 0; i < androidApps.length && out.length < limit; i++) {
            const a = androidApps[i];
            if (a.name.toLowerCase().indexOf(q) >= 0 || a.summary.toLowerCase().indexOf(q) >= 0 || a.pkg.toLowerCase() === q)
                out.push(a);
        }
        return out;
    }

    // Recently updated Android apps, for Discover.
    function recentAndroid(count) {
        return shown(androidApps).sort((a, b) => b.lastUpdated - a.lastUpdated).slice(0, count);
    }

    readonly property var antiFeatureText: ({
            "Ads": qsTr("Shows advertising"),
            "Tracking": qsTr("Tracks or reports your activity"),
            "NonFreeNet": qsTr("Relies on a service that isn't free software"),
            "NonFreeAdd": qsTr("Promotes add-ons that aren't free software"),
            "NonFreeDep": qsTr("Needs software that isn't free, which may include Google services"),
            "NonFreeAssets": qsTr("Contains media that isn't free"),
            "NoSourceSince": qsTr("Its source code is no longer available"),
            "KnownVuln": qsTr("Has a known security problem"),
            "TetheredNet": qsTr("Only works with its developer's own server"),
            "DisabledAlgorithm": qsTr("Signed with a weak algorithm")
        })

    // Android permissions in plain words; trivial ones (network state,
    // vibration) are left out.
    readonly property var permissionText: ({
            "android.permission.INTERNET": qsTr("Use the internet"),
            "android.permission.ACCESS_FINE_LOCATION": qsTr("Know your precise location"),
            "android.permission.ACCESS_COARSE_LOCATION": qsTr("Know your approximate location"),
            "android.permission.ACCESS_BACKGROUND_LOCATION": qsTr("Know your location while you're not using it"),
            "android.permission.CAMERA": qsTr("Use the camera"),
            "android.permission.RECORD_AUDIO": qsTr("Use the microphone"),
            "android.permission.READ_CONTACTS": qsTr("Read your contacts"),
            "android.permission.WRITE_CONTACTS": qsTr("Change your contacts"),
            "android.permission.READ_CALENDAR": qsTr("Read your calendar"),
            "android.permission.WRITE_CALENDAR": qsTr("Change your calendar"),
            "android.permission.READ_SMS": qsTr("Read your text messages"),
            "android.permission.SEND_SMS": qsTr("Send text messages"),
            "android.permission.RECEIVE_SMS": qsTr("Receive text messages"),
            "android.permission.CALL_PHONE": qsTr("Make phone calls"),
            "android.permission.READ_PHONE_STATE": qsTr("See your phone's status and identity"),
            "android.permission.READ_CALL_LOG": qsTr("Read your call history"),
            "android.permission.READ_EXTERNAL_STORAGE": qsTr("Read files on this phone"),
            "android.permission.WRITE_EXTERNAL_STORAGE": qsTr("Change files on this phone"),
            "android.permission.MANAGE_EXTERNAL_STORAGE": qsTr("Read and change all files on this phone"),
            "android.permission.READ_MEDIA_IMAGES": qsTr("Read your photos"),
            "android.permission.READ_MEDIA_VIDEO": qsTr("Read your videos"),
            "android.permission.READ_MEDIA_AUDIO": qsTr("Read your music and audio"),
            "android.permission.POST_NOTIFICATIONS": qsTr("Show notifications"),
            "android.permission.BLUETOOTH_CONNECT": qsTr("Connect to Bluetooth devices"),
            "android.permission.BLUETOOTH_SCAN": qsTr("Find Bluetooth devices nearby"),
            "android.permission.NEARBY_WIFI_DEVICES": qsTr("Find Wi-Fi devices nearby"),
            "android.permission.BODY_SENSORS": qsTr("Read body sensors"),
            "android.permission.ACTIVITY_RECOGNITION": qsTr("Recognise your physical activity"),
            "android.permission.SYSTEM_ALERT_WINDOW": qsTr("Draw over other apps"),
            "android.permission.REQUEST_INSTALL_PACKAGES": qsTr("Install other apps"),
            "android.permission.RECEIVE_BOOT_COMPLETED": qsTr("Start when the phone starts"),
            "android.permission.FOREGROUND_SERVICE": qsTr("Keep running in the background"),
            "android.permission.WAKE_LOCK": qsTr("Keep the phone awake"),
            "android.permission.USE_BIOMETRIC": qsTr("Use biometric sign-in"),
            "android.permission.CHANGE_WIFI_STATE": qsTr("Change Wi-Fi settings"),
            "android.permission.WRITE_SETTINGS": qsTr("Change system settings")
        })

    // What an Android app needs that this phone may not give it, worst first:
    // [{severity: "block" | "warn", text}]. Only what can't run blocks.
    // need: {features, libraries, gms, abis, minSdk, antiFeatures}.
    function compatibility(need) {
        const device = androidDevice;
        const abis = device ? device.abis : ["arm64-v8a"];
        const sdk = device && device.sdk > 0 ? device.sdk : 33;
        const blocks = [], warns = [];
        const needAbis = need.abis || [];
        if (needAbis.length > 0 && !needAbis.some(a => abis.indexOf(a) >= 0))
            blocks.push(qsTr("Has no code for this phone's processor (only %1)").arg(needAbis.join(", ")));
        if ((need.minSdk || 0) > sdk) {
            const release = ({ "34": "14", "35": "15", "36": "16", "37": "17" })[String(need.minSdk)];
            blocks.push(release ? qsTr("Needs Android %1 or newer").arg(release) : qsTr("Needs a newer Android"));
        }
        if (device) {
            (need.libraries || []).filter(l => device.libraries.indexOf(l) < 0).forEach(l => {
                blocks.push(l === "com.google.android.maps" ? qsTr("Needs Google Maps, which this phone doesn't have") : qsTr("Needs the %1 library, which this phone doesn't have").arg(l));
            });
            if (need.gms && !device.gms)
                warns.push(qsTr("Needs Google Play services, so it may not work"));
            const said = {};
            (need.features || []).filter(f => device.features.indexOf(f) < 0).forEach(f => {
                const text = featureText(f);
                if (!said[text]) {
                    said[text] = true;
                    warns.push(text);
                }
            });
        }
        if ((need.antiFeatures || []).indexOf("NonFreeDep") >= 0 && !(need.gms && device && !device.gms))
            warns.push(qsTr("Needs another app that isn't free, often Google Play services, so it may not work"));
        return blocks.map(t => ({ "severity": "block", "text": t })).concat(warns.map(t => ({ "severity": "warn", "text": t })));
    }

    function featureText(f) {
        const starts = p => f.indexOf(p) === 0;
        if (starts("android.hardware.telephony"))
            return qsTr("Needs a phone radio");
        if (starts("android.hardware.camera"))
            return qsTr("Needs a camera");
        if (starts("android.hardware.bluetooth"))
            return qsTr("Needs Bluetooth");
        if (starts("android.hardware.nfc"))
            return qsTr("Needs NFC");
        if (starts("android.hardware.location.gps"))
            return qsTr("Needs GPS");
        if (starts("android.hardware.location"))
            return qsTr("Needs location");
        if (starts("android.hardware.usb"))
            return qsTr("Needs USB accessories");
        if (starts("android.hardware.sensor"))
            return qsTr("Needs a sensor this phone doesn't have");
        if (starts("android.software.leanback") || starts("android.hardware.type.television"))
            return qsTr("Made for TVs");
        if (starts("android.hardware.type.watch"))
            return qsTr("Made for watches");
        if (starts("android.hardware.type.automotive"))
            return qsTr("Made for cars");
        return qsTr("Needs %1, which this phone doesn't have").arg(f);
    }

    // An F-Droid entry's needs, in compatibility()'s terms. The catalogue
    // keeps only versions with code for this phone and its Android.
    function catalogueNeeds(app) {
        return {
            "features": (app.version && app.version.features) || [],
            "minSdk": app.version ? app.version.minSdk : 0,
            "antiFeatures": app.antiFeatures || []
        };
    }

    function describeAndroidPermissions(names) {
        const out = [];
        (names || []).forEach(function (name) {
            const text = permissionText[name];
            if (text && out.indexOf(text) < 0)
                out.push(text);
        });
        return out;
    }

    // F-Droid's categories onto the Store's.
    function androidCategoryIds(app) {
        const ids = [];
        (app.categories || []).forEach(function (c) {
            const l = c.toLowerCase();
            const id = /game|dice/.test(l) ? "game" : /music|audio|video|podcast|radio|player|sound|camera|recorder/.test(l) ? "audiovideo" : /develop|code|forge|terminal/.test(l) ? "development" : /educat|learn|language|science|math/.test(l) ? "education" : /draw|graphic|photo|gallery|image|paint/.test(l) ? "graphics" : /browser|email|messag|chat|social|network|connect|download|vpn|dns|firewall|feed|news|forum/.test(l) ? "network" : /office|note|document|ebook|reader|calendar|task|finance|writ/.test(l) ? "office" : /system|app manager|file|battery|keyboard|launcher|security|backup|store/.test(l) ? "system" : "utility";
            if (ids.indexOf(id) < 0)
                ids.push(id);
        });
        return ids;
    }

    function androidInCategory(id) {
        return androidApps.filter(a => androidCategoryIds(a).indexOf(id) >= 0);
    }

    function inspectApk(path) {
        apkInfo = null;
        root.openExternally("marathon-store://apk-inspect/" + encodeURIComponent(path));
        apkPoll.path = path;
        apkPoll.since = Math.floor(Date.now() / 1000) - 1;
        apkPoll.tries = 0;
        apkPoll.running = true;
    }

    function installApk(path, pkg, name) {
        const appId = "android:" + pkg;
        if (!isValidRef(appId))
            return;
        const next = Object.assign({}, jobs);
        next[appId] = {
            "appId": appId,
            "state": "pending",
            "percent": -1,
            "error": "",
            "ts": Math.floor(Date.now() / 1000)
        };
        jobs = next;
        if (name) {
            const names = Object.assign({}, _apkNames);
            names[appId] = name;
            _apkNames = names;
        }
        _setVerb(appId, "install");
        jobPollTimer.running = true;
        root.openExternally("marathon-store://apk-install/" + encodeURIComponent(path) + "?pkg=" + pkg + "&name=" + encodeURIComponent(name || pkg));
    }

    function openApkConfirmation(path) {
        pushRequested(Qt.resolvedUrl("../pages/AndroidAppPage.qml"), {
            "store": root,
            "apkPath": path
        });
        inspectApk(path);
    }

    property Timer _androidSyncPoll: Timer {
        id: androidSyncPoll
        property int tries: 0
        interval: 5000
        repeat: true
        onTriggered: {
            const before = root.androidSyncedAt;
            root.loadAndroidCatalog(false);
            if (++tries > 36 || root.androidSyncedAt > before)
                running = false;
        }
    }

    property Timer _apkPoll: Timer {
        id: apkPoll
        property string path: ""
        property real since: 0
        property int tries: 0
        interval: 400
        repeat: true
        onTriggered: {
            root.readLocalJson(root.stateDir + "/apk-inspect.json", function (data) {
                if (data && data.path === apkPoll.path && data.ts >= apkPoll.since) {
                    root.apkInfo = data;
                    apkPoll.running = false;
                } else if (++apkPoll.tries > 75) {
                    root.apkInfo = {
                        "ok": false,
                        "message": root.helperSilentError
                    };
                    apkPoll.running = false;
                }
            });
        }
    }

    property Settings _cache: Settings {
        location: root.cacheFile
    }

    property FolderListModel _progressFiles: FolderListModel {
        folder: "file://" + root.stateDir
        nameFilters: ["install-progress-*.json"]
        showDirs: false
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                root.adoptJobs();
        }
    }

    property Timer _jobPollTimer: Timer {
        id: jobPollTimer
        interval: 700
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollJobs()
    }

    // refresh-state rewrites installed.json and then updates.json, the latter
    // after a remote-ls that can take seconds; read both once it has had time.
    property Timer _stateRefreshTimer: Timer {
        id: stateRefreshTimer
        property int tries: 0
        interval: 500
        repeat: true
        onTriggered: {
            root.loadInstalled();
            root.loadUpdates();
            root.loadStoreSettings();
            if ((root.installedStateFresh && root.updateStateFresh) || ++tries >= 60) {
                stop();
                root.stateRefreshInFlight = false;
            }
        }
    }

    // Parsing the multi-megabyte F-Droid catalogue and serialising every
    // partial Flathub response used to contend with the Store's first frame.
    property Timer _androidCatalogTimer: Timer {
        id: androidCatalogTimer
        interval: 2500
        onTriggered: root.loadAndroidCatalog(true)
    }

    property Timer _catalogSaveTimer: Timer {
        id: catalogSaveTimer
        interval: 750
        onTriggered: root.writeCatalog()
    }

    // Stagger startup requests rather than opening six at once.
    property Timer _startupTimer: Timer {
        id: startupTimer
        property var queue: []
        interval: 150
        repeat: true
        onTriggered: {
            if (queue.length === 0) {
                running = false;
                return;
            }
            queue.shift()();
        }
    }
}
