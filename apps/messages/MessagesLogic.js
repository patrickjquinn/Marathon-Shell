.pragma library

const twoDigitCountryCodes = ["20", "27", "30", "31", "32", "33", "34", "36", "39", "40", "41", "43", "44", "45", "46", "47", "48", "49", "51", "52", "53", "54", "55", "56", "57", "58", "60", "61", "62", "63", "64", "65", "66", "81", "82", "84", "86", "90", "91", "92", "93", "94", "95", "98"];
const runGap = 5 * 60 * 1000;

function digits(number) {
    return String(number || "").replace(/\D/g, "");
}

function group(d) {
    const out = [];
    while (d.length > 4) {
        out.push(d.slice(0, 3));
        d = d.slice(3);
    }
    if (d.length > 0)
        out.push(d);
    return out.join(" ");
}

// Display grouping only; the stored number is never rewritten.
function formatNumber(number) {
    const raw = String(number || "").trim();
    if (/[*#,;pPwW]/.test(raw))
        return raw;
    const d = digits(raw);
    if (d.length === 0)
        return raw.charAt(0) === "+" ? "+" : "";
    if (raw.charAt(0) !== "+")
        return group(d);
    const ccLength = (d.charAt(0) === "1" || d.charAt(0) === "7") ? 1 : twoDigitCountryCodes.indexOf(d.slice(0, 2)) !== -1 ? 2 : 3;
    const rest = d.slice(ccLength);
    return "+" + d.slice(0, ccLength) + (rest.length > 0 ? " " + group(rest) : "");
}

// The trailing 9 digits drop trunk and country prefixes.
function sameNumber(a, b) {
    const x = digits(a);
    const y = digits(b);
    if (x.length === 0 || y.length === 0)
        return false;
    if (x.length < 9 || y.length < 9)
        return x === y;
    return x.slice(-9) === y.slice(-9);
}

function isPhoneNumber(text) {
    return /^\+?[\d\s\-().]+$/.test(text) && digits(text).length >= 3;
}

function normaliseNumber(text) {
    return (text.charAt(0) === "+" ? "+" : "") + digits(text);
}

function displayName(conversation) {
    return conversation.contactName || formatNumber(conversation.contactNumber);
}

function matches(query, name, number, text) {
    const q = query.toLowerCase();
    const qDigits = digits(q);
    return q === "" || (name || "").toLowerCase().includes(q)
        || (qDigits !== "" && digits(number).includes(qDigits))
        || (text || "").toLowerCase().includes(q);
}

function conversationMatches(c, query) {
    return matches(query, c.contactName, c.contactNumber, c.lastMessage);
}

function visibleConversations(conversations, pinnedIds, archivedIds, archive, query) {
    const list = conversations.filter(c => (archivedIds.indexOf(c.id) !== -1) === archive && conversationMatches(c, query));
    const pinned = c => pinnedIds.indexOf(c.id) !== -1;
    return list.filter(pinned).concat(list.filter(c => !pinned(c)));
}

function parseState(json) {
    let v = {};
    try {
        v = JSON.parse(json) || {};
    } catch (e) {
        console.warn("Messages: discarding unreadable state:", e);
    }
    return {
        pinned: Array.isArray(v.pinned) ? v.pinned : [],
        archived: Array.isArray(v.archived) ? v.archived : [],
        drafts: v.drafts && typeof v.drafts === "object" && !Array.isArray(v.drafts) ? v.drafts : {}
    };
}

function unreadTotal(conversations) {
    return conversations.reduce((n, c) => n + (c.unreadCount || 0), 0);
}

// Oldest first; a day label opens each day, a time closes each run of one side's messages.
function messageRows(messages) {
    return messages.map((m, i) => {
        const prev = messages[i - 1];
        const next = messages[i + 1];
        const day = new Date(m.timestamp).toDateString();
        return Object.assign({}, m, {
            showDay: !prev || new Date(prev.timestamp).toDateString() !== day,
            showTime: !next || next.isOutgoing !== m.isOutgoing || next.timestamp - m.timestamp > runGap
                || new Date(next.timestamp).toDateString() !== day
        });
    });
}
