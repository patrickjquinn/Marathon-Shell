.pragma library

// marathon-weatherd's forecast, for people: MET Norway's symbol codes as
// words and glyphs, units, and the one-line outlook.

function parse(symbol) {
    // MET spells two of its codes "lightssleet…" and "lightssnow…".
    const s = String(symbol || "").replace(/^lights(sleet|snow)/, "light$1");
    const m = /^(light|heavy)?(rain|sleet|snow)(showers)?(andthunder)?$/.exec(s);
    if (!m)
        return { base: s, intensity: "", showers: false, thunder: false };
    return { base: m[2], intensity: m[1] || "", showers: !!m[3], thunder: !!m[4] };
}

function condition(symbol) {
    const p = parse(symbol);
    switch (p.base) {
    case "clearsky":
        return qsTr("Clear");
    case "fair":
        return qsTr("Mostly clear");
    case "partlycloudy":
        return qsTr("Partly cloudy");
    case "cloudy":
        return qsTr("Cloudy");
    case "fog":
        return qsTr("Fog");
    case "rain":
    case "sleet":
    case "snow":
        break;
    default:
        return "";
    }
    const nouns = {
        "rain": p.showers ? qsTr("rain showers") : qsTr("rain"),
        "sleet": p.showers ? qsTr("sleet showers") : qsTr("sleet"),
        "snow": p.showers ? qsTr("snow showers") : qsTr("snow")
    };
    let text = p.intensity === "light" ? qsTr("Light %1").arg(nouns[p.base]) : p.intensity === "heavy" ? qsTr("Heavy %1").arg(nouns[p.base]) : nouns[p.base];
    text = text.charAt(0).toUpperCase() + text.slice(1);
    return p.thunder ? qsTr("%1 and thunder").arg(text) : text;
}

// A Phosphor glyph name for GlyphIcon.
function glyph(symbol, isDay) {
    const p = parse(symbol);
    if (p.thunder)
        return "cloud-lightning";
    switch (p.base) {
    case "clearsky":
        return isDay === false ? "moon" : "sun";
    case "fair":
    case "partlycloudy":
        return isDay === false ? "cloud-moon" : "cloud-sun";
    case "fog":
        return "cloud-fog";
    case "rain":
        return "cloud-rain";
    case "sleet":
    case "snow":
        return "cloud-snow";
    default:
        return "cloud";
    }
}

function temperature(celsius, fahrenheit) {
    if (celsius === null || celsius === undefined || isNaN(celsius))
        return "–";
    const value = Math.round(fahrenheit ? celsius * 9 / 5 + 32 : celsius);
    // -0 reads as a minus sign.
    return (value === 0 ? 0 : value) + "°";
}

function speed(metresPerSecond, milesPerHour) {
    if (metresPerSecond === null || metresPerSecond === undefined)
        return "–";
    return milesPerHour ? qsTr("%1 mph").arg(Math.round(metresPerSecond * 2.23694)) : qsTr("%1 km/h").arg(Math.round(metresPerSecond * 3.6));
}

// The direction the wind comes from, as a compass point.
function compass(degrees) {
    const points = [qsTr("N"), qsTr("NE"), qsTr("E"), qsTr("SE"), qsTr("S"), qsTr("SW"), qsTr("W"), qsTr("NW")];
    return points[Math.round(((degrees % 360) + 360) % 360 / 45) % 8];
}

function uvLevel(index) {
    if (index === null || index === undefined)
        return "";
    if (index < 3)
        return qsTr("Low");
    if (index < 6)
        return qsTr("Moderate");
    if (index < 8)
        return qsTr("High");
    if (index < 11)
        return qsTr("Very high");
    return qsTr("Extreme");
}

// A UTC instant as a Date whose UTC fields read as the location's clock.
function atLocation(unixSeconds, offsetSeconds) {
    return new Date((unixSeconds + (offsetSeconds || 0)) * 1000);
}

function clock(unixSeconds, offsetSeconds, twelveHour) {
    if (!unixSeconds)
        return "–";
    const d = atLocation(unixSeconds, offsetSeconds);
    const h = d.getUTCHours();
    const m = ("0" + d.getUTCMinutes()).slice(-2);
    if (twelveHour)
        return (h % 12 || 12) + ":" + m + " " + (h < 12 ? Qt.locale().amText : Qt.locale().pmText);
    return ("0" + h).slice(-2) + ":" + m;
}

// The hour axis label: "14" or "2 PM".
function hour(unixSeconds, offsetSeconds, twelveHour) {
    const h = atLocation(unixSeconds, offsetSeconds).getUTCHours();
    if (twelveHour)
        return (h % 12 || 12) + " " + (h < 12 ? Qt.locale().amText : Qt.locale().pmText);
    return ("0" + h).slice(-2);
}

// "2026-10-17" as a short weekday, via `names` (Sunday first).
function weekday(isoDate, names) {
    const parts = String(isoDate).split("-").map(Number);
    return names[new Date(Date.UTC(parts[0], parts[1] - 1, parts[2])).getUTCDay()];
}

// The hours from `now` on, every `step` hours, at most `count`.
function upcoming(hourly, nowSeconds, count, step) {
    const from = (hourly || []).filter(h => h.time > nowSeconds - 3600);
    const out = [];
    for (let i = 0; i < from.length && out.length < count; i += step)
        out.push(from[i]);
    return out;
}

// One line about the precipitation in the next 24 hours: when it starts
// or stops, and how much.
function outlook(hourly, nowSeconds, offsetSeconds, twelveHour) {
    const day = upcoming(hourly, nowSeconds, 24, 1);
    if (day.length === 0)
        return "";
    const wet = h => (h.precipitation || 0) >= 0.1;
    const total = day.reduce((sum, h) => sum + (h.precipitation || 0), 0);
    const amount = total >= 1 ? qsTr("about %1 mm").arg(Math.round(total)) : qsTr("under 1 mm");
    const kind = h => parse(h.symbol).base === "snow" ? qsTr("Snow") : parse(h.symbol).base === "sleet" ? qsTr("Sleet") : qsTr("Rain");
    if (wet(day[0])) {
        const stop = day.findIndex(h => !wet(h));
        if (stop < 0)
            return qsTr("%1 for the next 24 hours, %2").arg(kind(day[0])).arg(amount);
        return qsTr("%1 stopping around %2").arg(kind(day[0])).arg(clock(day[stop].time, offsetSeconds, twelveHour));
    }
    const start = day.findIndex(wet);
    if (start < 0)
        return qsTr("Dry for the next 24 hours");
    return qsTr("%1 from %2, %3").arg(kind(day[start])).arg(clock(day[start].time, offsetSeconds, twelveHour)).arg(amount);
}

// Where a day's low and high sit on the week's scale, 0 to 1.
function span(day, days) {
    const lows = days.map(d => d.low).filter(v => v !== null && v !== undefined);
    const highs = days.map(d => d.high).filter(v => v !== null && v !== undefined);
    const min = Math.min.apply(null, lows);
    const max = Math.max.apply(null, highs);
    const range = Math.max(1, max - min);
    return { from: (day.low - min) / range, to: (day.high - min) / range };
}
