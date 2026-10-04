import MarathonApp.Store
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

// Marathon Store: a Flathub catalogue with ODRS ratings and reviews.
//
// This file is the data layer and the navigation shell; the screens live in
// pages/ and components/ and reach everything here through `store`.
// Catalogue data comes from flathub.org's v2 API, ratings and reviews from
// the Open Desktop Ratings Service that GNOME Software and Discover use.
// Installs go through the marathon-store:// URL scheme to a shell-side
// handler that runs flatpak and writes per-app progress files to
// $XDG_RUNTIME_DIR, which this file polls.
MApp {
    id: root

    appId: "store"
    appName: "App Store"
    appIcon: "assets/icon.svg"

    readonly property string flathubApi: "https://flathub.org/api/v2"
    readonly property string odrsApi: "https://odrs.gnome.org/1.0/reviews/api"
    readonly property string stateDir: "/run/user/" + (typeof userUid !== "undefined" ? userUid : "1000") + "/marathon-store-state"
    readonly property real sf: Constants.scaleFactor || 1.0

    property var collections: ({})
    property var appOfTheDay: null
    property var appstreamCache: ({})
    property var summaryCache: ({})
    property var installedApps: []
    property var pendingUpdates: []
    // appId → the handler's last progress record: {state, percent, error}.
    property var jobs: ({})
    // Four collections load concurrently, so this counts fetches in flight
    // rather than being a bool that the first response would clear.
    property int catalogFetchesInFlight: 0
    readonly property bool catalogLoading: catalogFetchesInFlight > 0
    property string lastError: ""
    // Collections can come back with keys but no entries once the aarch64
    // filter has run, so "loaded" means apps were counted, not keys.
    readonly property int catalogAppCount: {
        let n = 0;
        for (const k in collections)
            n += (collections[k] || []).length;
        return n;
    }
    property int activeTab: 0

    // Flathub's main categories, in the order its own site lists them.
    readonly property var categories: [
        {
            "id": "audiovideo",
            "label": "Audio & Video",
            "icon": "music-notes"
        },
        {
            "id": "development",
            "label": "Developer Tools",
            "icon": "code"
        },
        {
            "id": "education",
            "label": "Education",
            "icon": "graduation-cap"
        },
        {
            "id": "game",
            "label": "Games",
            "icon": "game-controller"
        },
        {
            "id": "graphics",
            "label": "Graphics & Photo",
            "icon": "palette"
        },
        {
            "id": "healthfitness",
            "label": "Health & Fitness",
            "icon": "heartbeat"
        },
        {
            "id": "network",
            "label": "Internet",
            "icon": "globe"
        },
        {
            "id": "office",
            "label": "Productivity",
            "icon": "briefcase"
        },
        {
            "id": "science",
            "label": "Science",
            "icon": "flask"
        },
        {
            "id": "system",
            "label": "System",
            "icon": "gear"
        },
        {
            "id": "utility",
            "label": "Utilities",
            "icon": "wrench"
        }
    ]

    readonly property var heroApp: appOfTheDay || firstOf(["verified", "popular", "trending"])
    readonly property var trendingApps: take(collections["trending"], [heroApp], 3)
    readonly property var mobileApps: take(collections["mobile"], [heroApp].concat(trendingApps), 5)
    readonly property var newApps: take(collections["recently-added"], [heroApp].concat(trendingApps, mobileApps), 5)
    readonly property var topApps: take(collections["popular"], [], 24)
    readonly property var updateApps: pendingUpdates.map(u => installedEntry(u.app_id) || u)

    signal pushRequested(var component, var properties)
    signal popRequested

    // The JSX spec is drawn at scale 1. Sizes with no MSpacing / MRadius /
    // MTypography token go through here, or they stay at design size while
    // the tokenised chrome around them grows with the display's DPI.
    function dp(n) {
        return Math.round(n * root.sf);
    }

    // ── Lists ─────────────────────────────────────────────────

    function idOf(app) {
        return app ? (app.app_id || app.id || "") : "";
    }

    function firstOf(names) {
        for (let i = 0; i < names.length; i++) {
            const list = collections[names[i]];
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
        if (u.indexOf("https://dl.flathub.org/") === 0 || u.indexOf("https://flathub.org/") === 0)
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
        const full = appstreamCache[idOf(app)];
        return full ? safeImageUrl(full.icon || "") : "";
    }

    property int _iconTick: 0

    function ensureIcon(app) {
        const id = idOf(app);
        if (!id || (app && app.icon) || appstreamCache[id])
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
        startupTimer.queue = [() => loadAppOfTheDay(), () => loadCollection("verified"), () => loadCollection("trending"), () => loadCollection("popular"), () => loadCollection("mobile"), () => loadCollection("recently-added"), () => refreshState()];
        startupTimer.running = true;
    }

    function loadCollection(name) {
        catalogFetchesInFlight += 1;
        fetchJson(flathubApi + "/collection/" + name + "?page=1&per_page=30&locale=en", null, function (data, err) {
            root.catalogFetchesInFlight -= 1;
            if (err) {
                root.lastError = name + ": " + err;
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
            loadAppstream(data.app_id, function (full) {
                root.appOfTheDay = full;
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
            const next = Object.assign({}, root.appstreamCache);
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
                const next = Object.assign({}, root.summaryCache);
                next[appId] = summary;
                root.summaryCache = next;
                cb(summary);
            });
        });
    }

    // A whole Flathub collection for a list page, e.g.
    // "collection/category/game" or "collection/mobile".
    function loadList(source, cb) {
        fetchJson(flathubApi + "/" + source + "?page=1&per_page=60&locale=en", null, function (data, err) {
            cb(err ? [] : pickAarch64(data.hits || []), err);
        });
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
        fetchJson(flathubApi + "/search", body, function (data, err) {
            cb(err ? [] : (data.hits || []), err);
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
        return "App";
    }

    function ensureCategory(app) {
        const id = idOf(app);
        if (!id || _categoryFor[id] || (app.categories && app.categories.length > 0) || app.main_categories)
            return;
        loadAppstream(id, function (full) {
            if (!full || !full.categories || full.categories.length === 0)
                return;
            const next = Object.assign({}, root._categoryFor);
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
        if (!appId || _ratings[appId] !== undefined)
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
            const counts = {
                "1": d.star1 || 0,
                "2": d.star2 || 0,
                "3": d.star3 || 0,
                "4": d.star4 || 0,
                "5": d.star5 || 0
            };
            const total = counts[1] + counts[2] + counts[3] + counts[4] + counts[5];
            const sum = counts[1] + counts[2] * 2 + counts[3] * 3 + counts[4] * 4 + counts[5] * 5;
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
            const written = list.filter(r => r.description && !r.reported);
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
            return "today";
        if (days < 2)
            return "yesterday";
        if (days < 30)
            return days + " days ago";
        if (days < 365)
            return Math.floor(days / 30) + (days < 60 ? " month ago" : " months ago");
        return Math.floor(days / 365) + (days < 730 ? " year ago" : " years ago");
    }

    function releaseLine(release) {
        const when = timeAgo(Number(release.timestamp));
        return "Version " + release.version + (when !== "" ? " · " + when : "");
    }

    function reviewByline(review) {
        const when = timeAgo(Number(review.date_created));
        return (review.user_display || "Anonymous") + (when !== "" ? " · " + when : "");
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
                "icon": "globe",
                "label": "Internet",
                "detail": "Can connect to the network"
            });
        const fs = p.filesystems || [];
        const broad = fs.filter(f => /^(host|home|host-os|host-etc)(:rw)?$/.test(f));
        if (broad.length > 0)
            out.push({
                "icon": "folders",
                "label": "All your files",
                "detail": "Can read and change files outside its sandbox",
                "risky": true
            });
        // gvfs is GNOME's virtual-filesystem plumbing, not a user folder.
        const named = fs.filter(f => !/^xdg-run\/gvfs/.test(f));
        if (broad.length === 0 && named.length > 0)
            out.push({
                "icon": "folder",
                "label": "Some folders",
                "detail": named.map(f => f.replace(/^xdg-/, "").replace(/:(ro|rw|create)$/, "")).join(", ")
            });
        if (has(p.devices, "all"))
            out.push({
                "icon": "usb",
                "label": "All devices",
                "detail": "Camera, USB and other hardware",
                "risky": true
            });
        if (has(p.sockets, "pulseaudio"))
            out.push({
                "icon": "speaker-high",
                "label": "Audio",
                "detail": "Can play and record sound"
            });
        if (has(p.sockets, "x11") && !has(p.sockets, "wayland"))
            out.push({
                "icon": "monitor",
                "label": "Legacy display access",
                "detail": "Uses X11, which isolates apps from each other less well",
                "risky": true
            });
        if (has(p.sockets, "cups"))
            out.push({
                "icon": "printer",
                "label": "Printing",
                "detail": "Can send documents to printers"
            });
        if (has(p.features, "bluetooth") || has(p.devices, "bluetooth"))
            out.push({
                "icon": "bluetooth",
                "label": "Bluetooth",
                "detail": "Can talk to Bluetooth devices"
            });
        return out;
    }

    function infoRows(app, summary) {
        const rows = [];
        const add = (label, value, url) => {
            if (value)
                rows.push(url ? {
                    "label": label,
                    "value": value,
                    "url": url
                } : {
                    "label": label,
                    "value": value
                });
        };
        const release = app.releases && app.releases.length > 0 ? app.releases[0] : null;
        add("Developer", app.developer_name);
        add("Version", release ? release.version : "");
        add("Updated", release ? timeAgo(Number(release.timestamp)) : "");
        add("Installed size", summary ? formatSize(summary.installed_size) : "");
        add("License", app.project_license);
        if (app.urls) {
            add("Website", app.urls.homepage ? app.urls.homepage.replace(/^https?:\/\//, "").replace(/\/$/, "") : "", app.urls.homepage);
            add("Report a problem", app.urls.bugtracker ? "Bug tracker" : "", app.urls.bugtracker);
        }
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

    // The handler records flatpak's last error line; turn the common ones
    // into something a phone user can act on.
    function jobError(job) {
        const raw = job && job.error ? job.error : "";
        if (/No space left|min-free-space/i.test(raw))
            return "Not enough storage space on this phone.";
        if (/Could not resolve|Network|Couldn.t connect|timed out/i.test(raw))
            return "Couldn't reach Flathub. Check your connection and try again.";
        return raw !== "" ? raw : "Something went wrong.";
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

    function hasUpdate(appId) {
        const job = jobs[appId];
        if (job && job.state === "done")
            return false;
        return pendingUpdates.some(u => u.app_id === appId);
    }

    function isValidRef(appId) {
        if (typeof appId !== "string" || appId.indexOf("..") >= 0)
            return false;
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
        jobPollTimer.running = true;
        Qt.openUrlExternally("marathon-store://" + verb + "/" + appId);
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
        }
        jobPollTimer.running = true;
        Qt.openUrlExternally("marathon-store://update-all/x");
    }

    function openApp(appId) {
        if (isValidRef(appId))
            Qt.openUrlExternally("marathon-store://open/" + appId);
    }

    function jobRunning(job) {
        return job.state === "pending" || job.state === "installing" || job.state === "removing";
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
                // A record older than the job is the previous run's result.
                if (!data || !current || data.ts < current.ts)
                    return;
                const next = Object.assign({}, root.jobs);
                next[appId] = data;
                root.jobs = next;
                if (!root.jobRunning(data))
                    stateRefreshTimer.restart();
            });
        });
    }

    function loadInstalled() {
        readLocalJson(stateDir + "/installed.json", function (data) {
            const list = data && data.installed ? data.installed : [];
            root.installedApps = list.map(a => ({
                        "app_id": a.app_id,
                        "name": a.name,
                        "version": a.version
                    }));
        });
    }

    function loadUpdates() {
        readLocalJson(stateDir + "/updates.json", function (data) {
            root.pendingUpdates = data && data.updates ? data.updates : [];
        });
    }

    function refreshState() {
        loadInstalled();
        loadUpdates();
        Qt.openUrlExternally("marathon-store://refresh-state/all");
        stateRefreshTimer.restart();
    }

    // ── Navigation ────────────────────────────────────────────

    function openDetail(app) {
        pushRequested(detailPage, {
            "appId": idOf(app),
            "summaryApp": app
        });
    }

    function openCategory(id, label) {
        pushRequested(listPage, {
            "title": label,
            "source": "collection/category/" + id
        });
    }

    function openCollection(name, label) {
        pushRequested(listPage, {
            "title": label,
            "source": "collection/" + name
        });
    }

    function openScreenshots(shots, index) {
        pushRequested(screenshotPage, {
            "screenshots": shots,
            "startIndex": index
        });
    }

    function goBack() {
        popRequested();
    }

    Component.onCompleted: loadCatalog()

    Timer {
        id: jobPollTimer
        interval: 700
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollJobs()
    }

    // refresh-state rewrites installed.json and then updates.json, the latter
    // after a remote-ls that can take seconds; read both once it has had time.
    Timer {
        id: stateRefreshTimer
        interval: 2500
        onTriggered: {
            root.loadInstalled();
            root.loadUpdates();
        }
    }

    // Stagger startup requests rather than opening six at once.
    Timer {
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

    Component {
        id: detailPage
        AppDetailPage {
            store: root
        }
    }
    Component {
        id: listPage
        AppListPage {
            store: root
        }
    }
    Component {
        id: screenshotPage
        ScreenshotViewer {
            store: root
        }
    }

    content: Rectangle {
        color: MColors.background

        MStackView {
            id: navStack
            anchors.fill: parent
            initialItem: shell
            // MApp.handleBack only emits backPressed while navigationDepth > 0.
            onDepthChanged: root.navigationDepth = depth - 1
        }

        Connections {
            target: root
            function onPushRequested(component, properties) {
                navStack.push(component, properties);
            }
            function onPopRequested() {
                if (navStack.depth > 1)
                    navStack.pop();
            }
            function onBackPressed() {
                if (navStack.depth > 1)
                    navStack.pop();
            }
        }

        Component {
            id: shell

            Item {
                readonly property var titles: ["Discover", "Apps", "Search", "Installed"]

                MTopBar {
                    id: topBar
                    width: parent.width
                    title: parent.titles[root.activeTab]
                }

                StackLayout {
                    anchors.top: topBar.bottom
                    anchors.bottom: tabBar.top
                    width: parent.width
                    currentIndex: root.activeTab

                    DiscoverPage {
                        store: root
                    }
                    Loader {
                        active: root.activeTab === 1 || item !== null
                        sourceComponent: AppsPage {
                            store: root
                        }
                    }
                    Loader {
                        id: searchLoader
                        active: root.activeTab === 2 || item !== null
                        sourceComponent: SearchPage {
                            store: root
                        }
                        onLoaded: item.focusField()
                    }
                    Loader {
                        active: root.activeTab === 3 || item !== null
                        sourceComponent: InstalledPage {
                            store: root
                        }
                    }
                }

                MTabBar {
                    id: tabBar
                    anchors.bottom: parent.bottom
                    width: parent.width
                    activeTab: root.activeTab
                    tabs: [
                        {
                            "label": "Discover",
                            "icon": "compass"
                        },
                        {
                            "label": "Apps",
                            "icon": "squares-four"
                        },
                        {
                            "label": "Search",
                            "icon": "magnifying-glass"
                        },
                        {
                            "label": "Installed",
                            "icon": "download"
                        }
                    ]
                    onTabSelected: index => {
                        HapticService.light();
                        root.activeTab = index;
                        if (index === 2 && searchLoader.item)
                            searchLoader.item.focusField();
                    }
                }
            }
        }
    }
}
