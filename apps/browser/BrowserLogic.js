.pragma library

const historyLimit = 100;
const suggestionLimit = 8;

const searchEngines = [
    { name: "Google", url: "https://www.google.com/search?q=" },
    { name: "DuckDuckGo", url: "https://duckduckgo.com/?q=" },
    { name: "Bing", url: "https://www.bing.com/search?q=" },
    { name: "Brave Search", url: "https://search.brave.com/search?q=" },
    { name: "Ecosia", url: "https://www.ecosia.org/search?q=" }
];

const homepages = [
    { name: "Google", url: "https://www.google.com" },
    { name: "DuckDuckGo", url: "https://duckduckgo.com" },
    { name: "Bing", url: "https://www.bing.com" },
    { name: "Blank page", url: "about:blank" }
];

function parseList(json) {
    try {
        const v = JSON.parse(json);
        return Array.isArray(v) ? v : [];
    } catch (e) {
        return [];
    }
}

function isWebUrl(url) {
    return /^(https?:\/\/|about:)/i.test(String(url || ""));
}

// http and https look the same once the bar shows only the host.
function schemeBadge(url) {
    const u = String(url || "");
    if (/^https:\/\//i.test(u))
        return "secure";
    if (/^http:\/\//i.test(u))
        return "insecure";
    return "none";
}

// The authority ends at the first / ? or #, so "https://evil.com?x=@paypal.com"
// reads evil.com. The port stays: it is part of where you are.
function displayHost(url) {
    const u = String(url || "");
    const m = u.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/?#]+)/);
    if (!m)
        return u;
    return m[1].replace(/^.*@/, "").replace(/^www\./, "");
}

// What the address field's text opens: { url } or { error }.
function resolveInput(text, searchEngineUrl) {
    const input = String(text || "").trim();
    if (!input)
        return { error: "" };
    const scheme = input.toLowerCase().split(":")[0];
    if (/^(javascript|data|file):/i.test(input))
        return { error: "Browser can't open " + scheme + ": addresses" };
    let url = input;
    if (!isWebUrl(input))
        url = input.indexOf(".") !== -1 && input.indexOf(" ") === -1 ? "https://" + input : searchEngineUrl + encodeURIComponent(input);
    if (!isWebUrl(url))
        return { error: "Browser can't open this address" };
    return { url: url };
}

function suggestions(query, bookmarks, history, engineName) {
    const q = String(query || "").trim();
    if (!q)
        return [];
    const lower = q.toLowerCase();
    const out = [];
    if ((q.indexOf(".") !== -1 && q.indexOf(" ") === -1) || /^https?:\/\//i.test(q)) {
        const url = isWebUrl(q) ? q : "https://" + q;
        out.push({ kind: "go", title: "Go to " + url, subtitle: "", value: url });
    }
    out.push({ kind: "search", title: "Search " + engineName + " for \"" + q + "\"", subtitle: "", value: q });
    const seen = {};
    const add = (kind, list) => {
        for (const entry of list) {
            if (out.length >= suggestionLimit)
                return;
            const url = entry.url || "";
            const title = entry.title || "";
            if (!url || seen[url])
                continue;
            if (url.toLowerCase().indexOf(lower) === -1 && title.toLowerCase().indexOf(lower) === -1)
                continue;
            seen[url] = true;
            out.push({ kind: kind, title: title || url, subtitle: url, value: url });
        }
    };
    add("bookmark", bookmarks);
    add("history", history);
    return out;
}

function matches(list, query) {
    const q = String(query || "").trim().toLowerCase();
    if (!q)
        return list;
    return list.filter(e => String(e.url || "").toLowerCase().indexOf(q) !== -1 || String(e.title || "").toLowerCase().indexOf(q) !== -1);
}

function isBookmarked(bookmarks, url) {
    return bookmarks.some(b => b.url === url);
}

function addBookmark(bookmarks, url, title, now) {
    if (isBookmarked(bookmarks, url))
        return bookmarks;
    return bookmarks.concat([{ url: url, title: title || url, timestamp: now }]);
}

function removeBookmark(bookmarks, url) {
    return bookmarks.filter(b => b.url !== url);
}

function addHistory(history, url, title, now) {
    const old = history.find(h => h.url === url);
    if (old) {
        return history.map(h => h.url !== url ? h : Object.assign({}, h, {
            timestamp: now,
            visitCount: (h.visitCount || 1) + 1,
            title: title || h.title
        }));
    }
    return [{ url: url, title: title || url, timestamp: now, visitCount: 1 }].concat(history).slice(0, historyLimit);
}

function retitleHistory(history, url, title) {
    if (!title || !history.some(h => h.url === url && h.title !== title))
        return history;
    return history.map(h => h.url === url ? Object.assign({}, h, { title: title }) : h);
}

function removeHistory(history, url) {
    return history.filter(h => h.url !== url);
}

function dateGroup(timestamp, now) {
    const day = 24 * 60 * 60 * 1000;
    const diff = now - timestamp;
    if (diff < day)
        return "Today";
    if (diff < day * 2)
        return "Yesterday";
    if (diff < day * 7)
        return "This week";
    return "Older";
}

function tabRow(id, url, title, fresh) {
    return {
        tabId: id,
        url: url,
        title: title || "New tab",
        // WebEngineView takes seconds to spawn on the L5; show progress from t=0.
        isLoading: fresh,
        canGoBack: false,
        canGoForward: false,
        loadProgress: fresh ? 5 : 0,
        isCrashed: false,
        isNewTab: fresh,
        crashCount: 0,
        lastCrashAt: 0,
        loadError: "",
        failedUrl: "",
        thumbnail: ""
    };
}

function restoreTabs(json, homepage) {
    return parseList(json).map(t => tabRow(t.id, t.url && t.url !== "about:blank" ? t.url : homepage, t.title, false));
}

function saveTabs(rows) {
    return JSON.stringify(rows.map(t => ({ id: t.tabId, url: t.url, title: t.title })));
}

function nextTabId(rows) {
    return rows.reduce((m, t) => Math.max(m, t.tabId), 0) + 1;
}

function indexOfName(list, name) {
    return list.findIndex(e => e.name === name);
}

function indexOfUrl(list, url) {
    return list.findIndex(e => e.url === url);
}
