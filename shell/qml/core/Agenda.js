.pragma library

// The calendar's events that fall on a day, all-day ones first, then by
// time. The recurrence rules match the calendar's own (calendarmanagercpp).
function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function isoDate(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

function occursOn(event, day) {
    if (event.date === isoDate(day))
        return true;
    const recurring = event.recurring || "none";
    if (recurring === "none" || !event.date)
        return false;
    const parts = event.date.split("-").map(Number);
    const start = new Date(parts[0], parts[1] - 1, parts[2]);
    const target = new Date(day.getFullYear(), day.getMonth(), day.getDate());
    if (isNaN(start.getTime()) || target < start)
        return false;
    const days = Math.round((target - start) / 86400000);
    if (recurring === "daily")
        return true;
    if (recurring === "weekly")
        return days % 7 === 0;
    if (recurring === "monthly")
        return start.getDate() === target.getDate();
    return false;
}

function forDay(events, day) {
    return (events || []).filter(e => occursOn(e, day)).sort((a, b) => {
        if (!!a.allDay !== !!b.allDay)
            return a.allDay ? -1 : 1;
        return (a.time || "").localeCompare(b.time || "");
    });
}
