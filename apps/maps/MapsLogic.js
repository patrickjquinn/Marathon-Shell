.pragma library

// Metres from a maneuver's start at which it counts as reached.
var reachRadius = 25;
// Metres before a maneuver at which its spoken cue plays.
var cueRadius = 150;

// Nominatim search JSON -> places, or null when it can't be read.
function parseResults(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!Array.isArray(raw))
        return null;
    return raw.map(r => ({
        name: String(r.display_name || "").split(",")[0],
        address: String(r.display_name || ""),
        lat: parseFloat(r.lat),
        lon: parseFloat(r.lon),
        type: r.type ? String(r.type).replace(/_/g, " ") : ""
    })).filter(p => isFinite(p.lat) && isFinite(p.lon));
}

function formatDistance(meters) {
    const m = Math.max(0, Math.round(meters));
    if (m < 1000)
        return (m < 100 ? m : Math.round(m / 10) * 10) + " m";
    return (m / 1000).toFixed(1) + " km";
}

function formatDuration(seconds) {
    const total = Math.max(1, Math.round(seconds / 60));
    if (total < 60)
        return total + " min";
    return Math.floor(total / 60) + " h " + (total % 60) + " min";
}

// Valhalla maneuver type -> theme icon.
function maneuverIcon(type) {
    const name = {
        1: "depart", 2: "depart", 3: "depart",
        4: "arrive", 5: "arrive", 6: "arrive",
        9: "slight-right", 37: "slight-right",
        10: "right", 11: "right", 18: "right", 20: "right", 23: "right",
        16: "slight-left", 38: "slight-left",
        14: "left", 15: "left", 19: "left", 21: "left", 24: "left",
        12: "uturn", 13: "uturn",
        26: "roundabout", 27: "roundabout"
    }[type] || "straight";
    return "image://theme/icon-m-maneuver-" + name;
}

function isArrival(maneuver) {
    return !!maneuver && maneuver.type >= 4 && maneuver.type <= 6;
}

// [lon, lat] points of the route's GeoJSON line.
function routeCoords(geojson) {
    try {
        const fc = typeof geojson === "string" ? JSON.parse(geojson) : geojson;
        const f = fc.type === "FeatureCollection" ? fc.features[0] : fc;
        const g = f.type === "Feature" ? f.geometry : f;
        return g.coordinates || [];
    } catch (e) {
        return [];
    }
}

function distanceMeters(lat1, lon1, lat2, lon2) {
    const rad = Math.PI / 180;
    const dLat = (lat2 - lat1) * rad;
    const dLon = (lon2 - lon1) * rad;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Index of the maneuver being driven and the metres left to the next one,
// for a fix at lat/lon. `index` only moves forward.
function track(coords, maneuvers, index, lat, lon) {
    let i = index;
    let distance = -1;
    while (i + 1 < maneuvers.length) {
        const p = coords[maneuvers[i + 1].beginShapeIndex];
        if (!p)
            break;
        distance = distanceMeters(lat, lon, p[1], p[0]);
        if (distance > reachRadius)
            break;
        i++;
        distance = -1;
    }
    return { index: i, distance: distance };
}

// Road the route mostly follows after setting off.
function via(maneuvers) {
    const m = maneuvers && maneuvers.length > 1 ? maneuvers[1] : null;
    const names = m && m.streetNames;
    if (!names)
        return "";
    return Array.isArray(names) ? names.join(", ") : String(names);
}
