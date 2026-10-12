.pragma library

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// The alarm service stores times as "HH:MM".
function timeString(hour, minute) {
    return pad2(hour) + ":" + pad2(minute);
}

function parseTime(text) {
    const parts = (text || "0:0").split(":");
    return { hour: parseInt(parts[0]) || 0, minute: parseInt(parts[1]) || 0 };
}

// Days are 0 = Sunday … 6 = Saturday, as the alarm service uses them.
function toggleDay(days, day) {
    const next = days.filter(d => d !== day);
    if (next.length === days.length)
        next.push(day);
    return next.sort();
}

function repeatSummary(days, dayName) {
    const key = days.slice().sort().join(",");
    if (days.length === 7)
        return qsTr("Every day");
    if (key === "1,2,3,4,5")
        return qsTr("Weekdays");
    if (key === "0,6")
        return qsTr("Weekends");
    return [1, 2, 3, 4, 5, 6, 0].filter(d => days.indexOf(d) !== -1).map(dayName).join(" ");
}

function nextOccurrence(alarm, now) {
    if (!alarm.enabled)
        return null;
    const t = parseTime(alarm.time);
    const repeat = alarm.repeat || [];
    for (let i = 0; i < 8; ++i) {
        const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i, t.hour, t.minute);
        if (d > now && (repeat.length === 0 || repeat.indexOf(d.getDay()) !== -1))
            return d;
    }
    return null;
}

function nextAlarm(alarms, now) {
    let best = null;
    for (const alarm of alarms) {
        const when = nextOccurrence(alarm, now);
        if (when && (!best || when < best.when))
            best = { alarm: alarm, when: when };
    }
    return best;
}

function formatStopwatch(ms) {
    const s = Math.floor(ms / 1000);
    const h = Math.floor(s / 3600);
    const rest = pad2(Math.floor(s / 60) % 60) + ":" + pad2(s % 60) + "." + pad2(Math.floor(ms % 1000 / 10));
    return h > 0 ? h + ":" + rest : rest;
}

function formatCountdown(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor(seconds % 3600 / 60);
    const s = pad2(seconds % 60);
    return h > 0 ? h + ":" + pad2(m) + ":" + s : m + ":" + s;
}

function parseCities(json, defaults) {
    if (!json)
        return defaults;
    try {
        const v = JSON.parse(json);
        return Array.isArray(v) ? v : defaults;
    } catch (e) {
        return defaults;
    }
}

// Cities saved before zones were stored only have a fixed offset.
function zoneFor(city, known) {
    if (city.tz)
        return city.tz;
    const match = known.find(k => k.name === city.name);
    return match ? match.tz : "";
}

function offsetTime(offset, now) {
    const d = new Date(now.getTime() + offset * 3600000);
    const h = d.getUTCHours();
    return (h % 12 || 12) + ":" + pad2(d.getUTCMinutes()) + (h >= 12 ? " PM" : " AM");
}

function moveCity(cities, from, to) {
    if (from === to || from < 0 || to < 0 || from >= cities.length || to >= cities.length)
        return cities;
    const next = cities.slice();
    next.splice(to, 0, next.splice(from, 1)[0]);
    return next;
}

function filterCities(cities, query) {
    const q = query.toLowerCase();
    return cities.filter(c => c.name.toLowerCase().indexOf(q) !== -1);
}
