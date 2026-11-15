// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Pure helpers for Pacific's UI (no QML types), tested by
// ui/tests/tst_logic.qml.

.pragma library

// The host of a URL without "www.", or "".
function host(url) {
    var m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@/?#]*@)?([^/:?#]+)/i.exec(String(url || ""))
    return m ? m[1].toLowerCase().replace(/^www\./, "") : ""
}

// What the address bar shows for a page: the host for web pages (the
// whole URL while editing), the title for internal pages.
function displayUrl(url, title) {
    var s = String(url || "")
    if (s === "" || s === "about:blank")
        return ""
    if (s.indexOf("file://") === 0)
        return title || s.substring(s.lastIndexOf("/") + 1)
    return host(s) || s
}

// True for pages loaded over plain HTTP.
function insecure(url) {
    return String(url || "").indexOf("http:") === 0
}

// The reader page Pacific wrote for a tab.
function isReaderUrl(url) {
    var s = String(url || "")
    return s.indexOf("file://") === 0 && s.indexOf("/reader/tab-") > 0
}

// A one-letter tile for sites without an icon.
function initial(title, url) {
    var h = host(url)
    // Skip a short language or mobile label: en.wikipedia.org is "W".
    var labels = h.split(".")
    while (labels.length > 2 && labels[0].length <= 3 && !/^[0-9]+$/.test(labels[0]))
        labels.shift()
    h = labels.join(".")
    var s = h || String(title || "")
    return s.length > 0 ? s.charAt(0).toUpperCase() : "?"
}

// Escapes text shown with a rich text format (page titles are untrusted).
function escape(text) {
    return String(text === undefined || text === null ? "" : text)
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
}

// Bytes for people: "512 B", "1.4 MB" ("1,4 MB" in German).
function size(bytes) {
    var b = Number(bytes)
    if (!(b >= 0))
        return ""
    var units = ["B", "kB", "MB", "GB"]
    var i = 0
    while (b >= 1000 && i < units.length - 1) {
        b /= 1000
        i++
    }
    return (i === 0 ? Math.round(b) : b.toLocaleString(Qt.locale(), "f", b < 10 ? 1 : 0)) + " " + units[i]
}

// The engine's data types for Pacific.dataCleared's JSON: a bit set of
// WebProfile.DataType values, given the enum values.
function clearTypes(engine, types) {
    var t = 0
    if (engine.cookies_and_site_data)
        t |= types.cookies | types.localStorage | types.indexedDb | types.serviceWorkers
    if (engine.cache)
        t |= types.cache
    return t
}

// Seconds since a time in ms (for WebProfile.clearData's sinceSeconds; 0
// clears everything).
function sinceSeconds(sinceMs, nowMs) {
    if (!sinceMs)
        return 0
    return Math.max(1, Math.round((nowMs - sinceMs) / 1000))
}

// The tab to show after a horizontal swipe on the address bar: dx < 0
// (swiping left) goes to the next tab.
function swipeStep(dx, threshold) {
    if (dx <= -threshold)
        return 1
    if (dx >= threshold)
        return -1
    return 0
}

// Zoom steps offered by the page menu.
var zoomSteps = [0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

function zoomStep(current, direction) {
    var c = Number(current) || 1.0
    if (direction > 0) {
        for (var i = 0; i < zoomSteps.length; ++i)
            if (zoomSteps[i] > c + 0.001)
                return zoomSteps[i]
        return zoomSteps[zoomSteps.length - 1]
    }
    for (var j = zoomSteps.length - 1; j >= 0; --j)
        if (zoomSteps[j] < c - 0.001)
            return zoomSteps[j]
    return zoomSteps[0]
}

// The user-facing name of a permission (PermissionRequest.Kind order).
function permissionKey(kind) {
    return ["location", "camera", "microphone", "camera+microphone", "screen", "notifications",
            "device-info", "storage", "pointer-lock", "media-keys", "clipboard", "other"][kind] || "other"
}

// The site-settings key that remembers an answer for a permission, or "".
function permissionSetting(kind) {
    var k = permissionKey(kind)
    var known = { "location": 1, "camera": 1, "microphone": 1, "notifications": 1, "clipboard": 1 }
    return known[k] ? "perm." + k : ""
}

// Words for time since `ms` ("now", "5 min", "3 h", "2 d").
function ago(ms, nowMs) {
    var s = Math.max(0, Math.round((nowMs - ms) / 1000))
    if (s < 60)
        return "now"
    if (s < 3600)
        return Math.round(s / 60) + " min"
    if (s < 86400)
        return Math.round(s / 3600) + " h"
    return Math.round(s / 86400) + " d"
}

// A stable hue (0..1) for a host's letter tile.
function hostHue(url) {
    var h = host(url)
    var n = 0
    for (var i = 0; i < h.length; ++i)
        n = (n * 31 + h.charCodeAt(i)) % 360
    return n / 360
}

// What the address bar shows for a page: the registrable domain
// (`siteOf`, from the app) for web pages, else displayUrl.
function barText(url, title, site) {
    var s = String(url || "")
    if (s.indexOf("http") === 0 && site)
        return site
    return displayUrl(s, title)
}

// A spell-checking dictionary's name (`en_GB`) as its language calls
// itself ("British English"), first letter capitalised; the code itself
// when the locale is unknown.
function languageName(code) {
    var l = Qt.locale(code)
    var name = l && l.name !== "C" ? l.nativeLanguageName : ""
    if (!name)
        return code
    return name.charAt(0).toLocaleUpperCase() + name.slice(1)
}

// The theme icon for a downloaded file, from its name's extension.
function fileIcon(name) {
    var m = /\.([a-z0-9]+)$/i.exec(String(name || ""))
    var ext = m ? m[1].toLowerCase() : ""
    var kinds = {
        pdf: "icon-m-file-pdf-light",
        zip: "icon-m-file-compressed", gz: "icon-m-file-compressed", xz: "icon-m-file-compressed",
        bz2: "icon-m-file-compressed", "7z": "icon-m-file-compressed", tar: "icon-m-file-compressed",
        png: "icon-m-file-image", jpg: "icon-m-file-image", jpeg: "icon-m-file-image", gif: "icon-m-file-image",
        webp: "icon-m-file-image", svg: "icon-m-file-image", avif: "icon-m-file-image",
        mp3: "icon-m-file-audio", ogg: "icon-m-file-audio", opus: "icon-m-file-audio", flac: "icon-m-file-audio",
        m4a: "icon-m-file-audio", wav: "icon-m-file-audio",
        mp4: "icon-m-file-video", webm: "icon-m-file-video", mkv: "icon-m-file-video", mov: "icon-m-file-video",
        txt: "icon-m-file-note-light", md: "icon-m-file-note-light",
        doc: "icon-m-file-formatted-light", docx: "icon-m-file-formatted-light", odt: "icon-m-file-formatted-light",
        xls: "icon-m-file-spreadsheet-light", xlsx: "icon-m-file-spreadsheet-light", ods: "icon-m-file-spreadsheet-light",
        ppt: "icon-m-file-presentation-light", pptx: "icon-m-file-presentation-light", odp: "icon-m-file-presentation-light",
        apk: "icon-m-file-apk", rpm: "icon-m-file-rpm", vcf: "icon-m-file-vcard"
    }
    return kinds[ext] || "icon-m-file-other-light"
}

// A permission request as the question its dialog asks.
function permissionQuestion(kind, site) {
    switch (permissionKey(kind)) {
    case "location": return qsTr("%1 wants to know your location").arg(site)
    case "camera": return qsTr("%1 wants to use your camera").arg(site)
    case "microphone": return qsTr("%1 wants to use your microphone").arg(site)
    case "camera+microphone": return qsTr("%1 wants to use your camera and microphone").arg(site)
    case "notifications": return qsTr("%1 wants to show notifications").arg(site)
    case "clipboard": return qsTr("%1 wants to read the clipboard").arg(site)
    case "screen": return qsTr("%1 wants to see your screen").arg(site)
    default: return qsTr("%1 asks for a permission").arg(site)
    }
}

// The theme icon for a permission (the Sailfish Browser's).
function permissionIcon(kind) {
    var icons = { "location": "location", "camera": "camera", "microphone": "microphone",
                  "camera+microphone": "camera", "notifications": "notifications", "clipboard": "popup" }
    var k = icons[permissionKey(kind)]
    return "image://theme/icon-m-browser-" + (k || "permissions")
}
