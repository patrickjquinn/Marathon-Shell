// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Text and link helpers shared by the pages.
//
// The Rust side sends keys, not English, for everything it says itself
// (apps/reef/src/rows.rs: message, and the bridge's busyText), so the text
// is translated here with qsTr. Errors that come from the network or the
// licence library are shown as they are.
//
// Links in the catalogue are developer-controlled: only https:// URLs are
// ever opened.

.pragma library

// busyText: "refreshing", "refreshing_licences".
function busyText(code) {
    switch (code) {
    case "": return ""
    case "refreshing": return qsTr("Refreshing")
    case "refreshing_licences": return qsTr("Refreshing licences")
    default: return qsTr("Working")
    }
}

function messageLine(line) {
    if (line.charAt(0) !== "\u001e")
        return line
    var p = line.substring(1).split("\u001f")
    switch (p[0]) {
    case "no_licence_store": return qsTr("No place to store licences (HOME is not set).")
    case "licence_remove_failed": return qsTr("Could not remove the licence: %1").arg(p[1])
    case "catalogue_missing":
        return qsTr("Reef has no catalogue for Marathon (%1) yet.").arg(p[1])
    case "catalogue_download_failed": return qsTr("Could not download the catalogue: %1").arg(p[1])
    case "no_licence_server": return qsTr("No licence service is configured.")
    case "revocations_unsigned": return qsTr("The list of refunded licences is not signed.")
    case "licence_add_failed": return qsTr("The licence was not added: %1").arg(p[1])
    case "claim_failed": return qsTr("Could not start the purchase: %1").arg(p[1])
    case "worker_failed": return qsTr("Could not start the background work: %1").arg(p[1])
    default: return p.join(" ")
    }
}

// When a background service starts (the catalogue's services[].starts).
function startsText(starts) {
    switch (starts) {
    case "login": return qsTr("starts when you log in")
    case "boot": return qsTr("starts when the phone starts")
    case "schedule": return qsTr("runs on a schedule")
    case "on_demand": return qsTr("starts when needed")
    default: return qsTr("runs in the background")
    }
}

// lastError messages; lastError may hold several lines.
function message(text) {
    if (!text)
        return ""
    return text.split("\n").map(messageLine).join("\n")
}

// An absolute https:// URL with a host and no whitespace or control
// characters (the rule reef-backend's catalogue parser applies too).
function isHttps(url) {
    return typeof url === "string" && url.length <= 2048
            && /^https:\/\/[^\/]/.test(url) && !/[\s\u0000-\u001f\u007f]/.test(url)
}

function openHttps(url) {
    if (isHttps(url))
        Qt.openUrlExternally(url)
}

// A plain https:// URL for the licence service setting.
function isServiceUrl(url) {
    return isHttps(url) && url.indexOf("?") < 0 && url.indexOf("#") < 0
}

// A Sailjail permission (the catalogue's names, from the app's desktop
// file) in words, with a theme icon: {label, icon}. Names not listed are
// split at their capitals ("ShoalPush" is "Shoal push").
function permission(name) {
    switch (name) {
    case "Internet": return { label: qsTr("Internet"), icon: "image://theme/icon-m-website" }
    case "Bluetooth": return { label: qsTr("Bluetooth"), icon: "image://theme/icon-m-bluetooth" }
    case "Connman": return { label: qsTr("Network settings"), icon: "image://theme/icon-m-wlan" }
    case "Location": return { label: qsTr("Your location"), icon: "image://theme/icon-m-location" }
    case "Camera": return { label: qsTr("Camera"), icon: "image://theme/icon-m-camera" }
    case "Microphone": return { label: qsTr("Microphone"), icon: "image://theme/icon-m-mic" }
    case "Audio": return { label: qsTr("Sound"), icon: "image://theme/icon-m-speaker" }
    case "Contacts": return { label: qsTr("Contacts"), icon: "image://theme/icon-m-people" }
    case "Calendar": return { label: qsTr("Calendar"), icon: "image://theme/icon-m-date" }
    case "CommunicationHistory": return { label: qsTr("Messages and call history"), icon: "image://theme/icon-m-sms" }
    case "Messages": return { label: qsTr("Send messages"), icon: "image://theme/icon-m-message" }
    case "Phone": return { label: qsTr("Phone calls"), icon: "image://theme/icon-m-phone" }
    case "Accounts": return { label: qsTr("Your accounts"), icon: "image://theme/icon-m-person" }
    case "Synchronization": return { label: qsTr("Account sync"), icon: "image://theme/icon-m-sync" }
    case "Secrets": return { label: qsTr("Saved passwords and keys"), icon: "image://theme/icon-m-keys" }
    case "Privileged": return { label: qsTr("System data (contacts, calendar, messages)"), icon: "image://theme/icon-m-warning" }
    case "Pictures": return { label: qsTr("Pictures"), icon: "image://theme/icon-m-image" }
    case "Videos": return { label: qsTr("Videos"), icon: "image://theme/icon-m-video" }
    case "Music": return { label: qsTr("Music"), icon: "image://theme/icon-m-music" }
    case "Documents": return { label: qsTr("Documents"), icon: "image://theme/icon-m-document" }
    case "Downloads": return { label: qsTr("Downloads"), icon: "image://theme/icon-m-downloads" }
    case "PublicDir": return { label: qsTr("Public folder"), icon: "image://theme/icon-m-folder" }
    case "RemovableMedia": return { label: qsTr("Memory card"), icon: "image://theme/icon-m-sd-card" }
    case "MediaIndexing": return { label: qsTr("Media library"), icon: "image://theme/icon-m-folder" }
    case "Thumbnails": return { label: qsTr("Thumbnails"), icon: "image://theme/icon-m-image" }
    case "Sharing": return { label: qsTr("Sharing"), icon: "image://theme/icon-m-share" }
    case "Notifications": return { label: qsTr("Notifications"), icon: "image://theme/icon-m-notifications" }
    case "UnifiedPush": return { label: qsTr("Push notifications"), icon: "image://theme/icon-m-notifications" }
    case "ShipwrightLicences": return { label: qsTr("Your Reef licences"), icon: "image://theme/icon-m-certificates" }
    case "ShoalPilot": return { label: qsTr("The Pilot assistant service"), icon: "image://theme/icon-m-chat" }
    case "KeelPolicy": return { label: qsTr("Camera and sound settings"), icon: "image://theme/icon-m-sounds" }
    }
    var words = String(name).replace(/([a-z])([A-Z])/g, "$1 $2")
    return { label: words.charAt(0).toUpperCase() + words.slice(1).toLowerCase(),
             icon: "image://theme/icon-m-other" }
}

// The package's own licence (an SPDX expression) for people: Shipwright's
// and other LicenseRef- licences are "Proprietary".
function licence(spdx) {
    if (!spdx)
        return ""
    if (spdx === "LicenseRef-Shipwright-Proprietary")
        return qsTr("Proprietary (Shipwright)")
    if (spdx.indexOf("LicenseRef-") === 0)
        return qsTr("Proprietary")
    // A bundle of many ("ASL 2.0 and MIT and MPLv2.0 and ...", a Rust
    // app's dependencies) is cut to the first two: seven lines of it
    // buried the page.
    var parts = spdx.split(/ (?:and|AND) /)
    var shown = parts.slice(0, 2).map(function(p) { return p.replace(/-or-later$/, "+").replace(/-only$/, "") })
    if (parts.length > 3)
        return qsTr("%1 and %n more", "", parts.length - 2).arg(shown.join(", "))
    return spdx.replace(/-or-later$/, "+").replace(/-only$/, "")
}

// "2026-10-11" as the phone's locale writes a short date ("11 Oct 2026").
function date(ymd) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd || "")
    if (!m)
        return ""
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
    return d.toLocaleDateString(Qt.locale(), "d MMM yyyy")
}

// What it costs, for the list chips and the page: "Free", "Paid",
// "Subscription", or what the person already has.
function price(model, licensed) {
    if (model === "one_off")
        return licensed ? qsTr("Licensed") : qsTr("Paid")
    if (model === "subscription")
        return licensed ? qsTr("Subscribed") : qsTr("Subscription")
    return qsTr("Free")
}

// The catalogue's changelog JSON (packageDetails' changelogJson), or [].
function changelog(json) {
    try {
        var list = JSON.parse(json || "[]")
        return Array.isArray(list) ? list : []
    } catch (e) {
        return []
    }
}

// Disclosure lines grouped under what they share: an app that brings
// several packages lists "Runs scripts as the system administrator when
// installed or removed: <what>" once per package. Lines "<head>: <rest>"
// whose head appears more than once become one { text: head, items: [rest,
// ...] }, in the order the head first appears; the others stay
// { text: line, items: [] }.
function groupLines(lines) {
    var heads = {}
    var split = lines.map(function(line) {
        var at = String(line).indexOf(": ")
        var head = at > 0 ? line.substring(0, at) : ""
        if (head)
            heads[head] = (heads[head] || 0) + 1
        return { line: String(line), head: head, rest: at > 0 ? line.substring(at + 2) : "" }
    })
    var out = []
    var groups = {}
    split.forEach(function(s) {
        if (s.head && heads[s.head] > 1) {
            if (!groups[s.head]) {
                groups[s.head] = { text: s.head, items: [] }
                out.push(groups[s.head])
            }
            groups[s.head].items.push(s.rest)
        } else {
            out.push({ text: s.line, items: [] })
        }
    })
    return out
}
