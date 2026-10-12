.pragma library

const twoDigitCountryCodes = ["20", "27", "30", "31", "32", "33", "34", "36", "39", "40", "41", "43", "44", "45", "46", "47", "48", "49", "51", "52", "53", "54", "55", "56", "57", "58", "60", "61", "62", "63", "64", "65", "66", "81", "82", "84", "86", "90", "91", "92", "93", "94", "95", "98"];

// Short codes networks route to emergency services, with or without a SIM.
const emergencyNumbers = ["112", "911", "999", "000", "110", "119", "118", "08"];

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

// Display grouping only; never rewrites the stored number.
function format(number) {
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

// Trailing 9 digits drop trunk/country prefixes: "+1 555 123 4567" == "5551234567".
function sameNumber(a, b) {
    const x = digits(a);
    const y = digits(b);
    if (x.length === 0 || y.length === 0)
        return false;
    if (x.length < 9 || y.length < 9)
        return x === y;
    return x.slice(-9) === y.slice(-9);
}

function isEmergency(number) {
    return emergencyNumbers.indexOf(String(number || "").trim()) !== -1;
}

function duration(seconds) {
    const s = Math.max(0, Math.floor(Number(seconds) || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = (s % 60 < 10 ? "0" : "") + s % 60;
    return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + sec : m + ":" + sec;
}

// History rows carry seconds or milliseconds depending on the backend.
function timestampMs(ts) {
    const n = Number(ts);
    if (!Number.isFinite(n) || n <= 0)
        return 0;
    return n < 1e11 ? n * 1000 : n;
}

function filterContacts(contacts, query) {
    const q = String(query || "").trim().toLowerCase();
    if (q.length === 0)
        return contacts;
    const qDigits = digits(q);
    return contacts.filter(c => c && ((c.name || "").toLowerCase().indexOf(q) !== -1 || (qDigits.length > 0 && digits(c.phone).indexOf(qDigits) !== -1)));
}

function missedSince(history, sinceMs) {
    return (history || []).filter(c => c && c.type === "missed" && timestampMs(c.timestamp) > sinceMs).length;
}
