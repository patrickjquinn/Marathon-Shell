.pragma library

// Mirrors CalendarManagerCpp::getEventsForDate so the views can bind to the
// event list instead of calling into the service per day.

const repeatModes = ["none", "daily", "weekly", "monthly"];
// Minutes before the start; -1 is no reminder.
const reminderMinutes = [-1, 0, 5, 15, 30, 60, 1440];

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

function dateKey(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

function parseDate(key) {
    const p = String(key || "").split("-").map(Number);
    if (p.length !== 3 || p.some(isNaN))
        return new Date(NaN);
    return new Date(p[0], p[1] - 1, p[2], 12, 0, 0);
}

function timeString(hour, minute) {
    return pad(hour) + ":" + pad(minute);
}

function parseTime(text) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(text || ""));
    return m ? { hour: Number(m[1]), minute: Number(m[2]) } : { hour: 12, minute: 0 };
}

function addMinutes(time, minutes) {
    const t = parseTime(time);
    const total = (((t.hour * 60 + t.minute + minutes) % 1440) + 1440) % 1440;
    return timeString(Math.floor(total / 60), total % 60);
}

// An end at or before the start is on the next day.
function duration(start, end) {
    const s = parseTime(start);
    const e = parseTime(end);
    return ((e.hour * 60 + e.minute - s.hour * 60 - s.minute) % 1440 + 1440) % 1440;
}

function endsNextDay(event) {
    return !event.allDay && !!event.endTime && String(event.endTime) < String(event.time);
}

function dayNumber(d) {
    return Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
}

function occursOn(event, date) {
    const key = dateKey(date);
    if (event.date === key)
        return true;
    const base = parseDate(event.date);
    if (isNaN(base.getTime()) || key < event.date)
        return false;
    switch (event.recurring) {
    case "daily":
        return true;
    case "weekly":
        return (dayNumber(date) - dayNumber(base)) % 7 === 0;
    case "monthly":
        return base.getDate() === date.getDate();
    default:
        return false;
    }
}

function byTime(a, b) {
    if (!!a.allDay !== !!b.allDay)
        return a.allDay ? -1 : 1;
    return String(a.time || "").localeCompare(String(b.time || ""));
}

function eventsOn(events, date) {
    return (events || []).filter(e => occursOn(e, date)).sort(byTime);
}

function sorted(events) {
    return (events || []).slice().sort((a, b) => String(a.date).localeCompare(String(b.date)) || byTime(a, b));
}

function search(events, query) {
    const q = String(query || "").trim().toLowerCase();
    if (q === "")
        return [];
    return sorted((events || []).filter(e => [e.title, e.location, e.description].map(v => String(v || "")).join("\n").toLowerCase().indexOf(q) !== -1));
}

// Today's events that have not finished yet, all-day ones first.
function upcoming(events, now) {
    const t = timeString(now.getHours(), now.getMinutes());
    return eventsOn(events, now).filter(e => e.allDay || String(e.time) >= t || endsNextDay(e) || (!!e.endTime && String(e.endTime) > t));
}
