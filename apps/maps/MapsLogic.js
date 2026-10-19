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

var icons = {
    depart: "image://theme/icon-m-maneuver-depart",
    arrive: "image://theme/icon-m-maneuver-arrive",
    left: "image://theme/icon-m-maneuver-left",
    right: "image://theme/icon-m-maneuver-right",
    slightLeft: "image://theme/icon-m-maneuver-slight-left",
    slightRight: "image://theme/icon-m-maneuver-slight-right",
    uturn: "image://theme/icon-m-maneuver-uturn",
    roundabout: "image://theme/icon-m-maneuver-roundabout",
    straight: "image://theme/icon-m-maneuver-straight"
};

// Valhalla maneuver type -> theme icon.
function maneuverIcon(type) {
    return icons[{
        1: "depart", 2: "depart", 3: "depart",
        4: "arrive", 5: "arrive", 6: "arrive",
        9: "slightRight", 37: "slightRight",
        10: "right", 11: "right", 18: "right", 20: "right", 23: "right",
        16: "slightLeft", 38: "slightLeft",
        14: "left", 15: "left", 19: "left", 21: "left", 24: "left",
        12: "uturn", 13: "uturn",
        26: "roundabout", 27: "roundabout"
    }[type] || "straight"];
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

// Distance (m) and time (s) left on the route from maneuver `index`, with
// `toNext` metres to go before the next one.
function remaining(maneuvers, index, toNext) {
    if (!maneuvers || index >= maneuvers.length)
        return { distance: 0, time: 0 };
    const m = maneuvers[index];
    const length = (m.length || 0) * 1000;
    const left = Math.min(length, toNext >= 0 ? toNext : length);
    let distance = left;
    let time = length > 0 ? (m.time || 0) * left / length : 0;
    for (let i = index + 1; i < maneuvers.length; i++) {
        distance += (maneuvers[i].length || 0) * 1000;
        time += maneuvers[i].time || 0;
    }
    return { distance: distance, time: time };
}

// No WebGL context can't be fixed by retrying; a lost renderer can.
function mapFailureIsPermanent(message) {
    return /WebGL|context/i.test(String(message || ""));
}

// Readable labels for common OSM types; unknown ones ("yes") stay unnamed.
const placeKinds = {
    "house": QT_TR_NOOP("Address"), "residential": QT_TR_NOOP("Street"), "primary": QT_TR_NOOP("Road"),
    "secondary": QT_TR_NOOP("Road"), "tertiary": QT_TR_NOOP("Road"), "unclassified": QT_TR_NOOP("Road"),
    "city": QT_TR_NOOP("City"), "town": QT_TR_NOOP("Town"), "village": QT_TR_NOOP("Village"),
    "hamlet": QT_TR_NOOP("Village"), "suburb": QT_TR_NOOP("District"), "neighbourhood": QT_TR_NOOP("Neighbourhood"),
    "administrative": QT_TR_NOOP("Area"), "postcode": QT_TR_NOOP("Postcode"), "restaurant": QT_TR_NOOP("Restaurant"),
    "cafe": QT_TR_NOOP("Café"), "pub": QT_TR_NOOP("Pub"), "bar": QT_TR_NOOP("Bar"),
    "fast food": QT_TR_NOOP("Fast food"), "hotel": QT_TR_NOOP("Hotel"), "museum": QT_TR_NOOP("Museum"),
    "attraction": QT_TR_NOOP("Attraction"), "park": QT_TR_NOOP("Park"), "station": QT_TR_NOOP("Station"),
    "bus stop": QT_TR_NOOP("Bus stop"), "supermarket": QT_TR_NOOP("Supermarket"), "school": QT_TR_NOOP("School"),
    "university": QT_TR_NOOP("University"), "hospital": QT_TR_NOOP("Hospital"), "pharmacy": QT_TR_NOOP("Pharmacy"),
    "bridge": QT_TR_NOOP("Bridge"), "place of worship": QT_TR_NOOP("Place of worship"), "parking": QT_TR_NOOP("Parking"),
    "fuel": QT_TR_NOOP("Fuel station"), "aerodrome": QT_TR_NOOP("Airport"), "library": QT_TR_NOOP("Library")
};

function placeKind(type) {
    const kind = placeKinds[String(type || "").toLowerCase()];
    return kind ? qsTr(kind) : "";
}

// "Bridge · Tower Bridge Road, London": kind, then the address after the name.
function placeLine(place) {
    const address = String(place.address || "");
    const rest = address.indexOf(place.name + ", ") === 0 ? address.slice(place.name.length + 2) : address;
    const kind = placeKind(place.type);
    return kind && rest ? kind + " · " + rest : kind || rest;
}

const recentLimit = 10;

function parseList(json) {
    try {
        const v = JSON.parse(json);
        return Array.isArray(v) ? v : [];
    } catch (e) {
        return [];
    }
}

// The chosen place first; an earlier pick of the same place moves up.
function addRecent(recents, place) {
    const same = p => p.name === place.name && Math.abs(p.lat - place.lat) < 1e-6 && Math.abs(p.lon - place.lon) < 1e-6;
    const entry = { name: place.name, address: place.address, lat: place.lat, lon: place.lon, type: place.type || "" };
    return [entry].concat(recents.filter(p => !same(p))).slice(0, recentLimit);
}

// Nominatim prefers results inside this box but still returns others.
function searchUrl(query, fix) {
    let url = "https://nominatim.openstreetmap.org/search?q=" + encodeURIComponent(query) + "&format=json&limit=10";
    if (fix)
        url += "&viewbox=" + [fix.lon - 0.5, fix.lat + 0.5, fix.lon + 0.5, fix.lat - 0.5].map(v => v.toFixed(4)).join(",");
    return url;
}

// {lat, lon} from the saved JSON, or null.
function parseFix(json) {
    try {
        const v = JSON.parse(json);
        return v && isFinite(v.lat) && isFinite(v.lon) ? { lat: Number(v.lat), lon: Number(v.lon) } : null;
    } catch (e) {
        return null;
    }
}

// What to tell the user when Valhalla gives no route.
function routeFailure(error, mode) {
    const e = String(error || "");
    if (/no (path|route)|unable to find|cannot reach|no suitable edges/i.test(e)) {
        if (mode === "pedestrian")
            return qsTr("There's no walking route to this place.");
        if (mode === "bicycle")
            return qsTr("There's no cycling route to this place.");
        return qsTr("There's no driving route to this place.");
    }
    if (/timed out/i.test(e))
        return qsTr("Finding a route took too long. Check your internet connection and try again.");
    return qsTr("Couldn't find a route to this place. Check your internet connection and try again.");
}

// {place, mode} saved when navigation started, or null.
function parseSavedRoute(json) {
    try {
        const v = JSON.parse(json);
        return v && v.place && isFinite(v.place.lat) && isFinite(v.place.lon) ? v : null;
    } catch (e) {
        return null;
    }
}

// The text a link asks Maps to search for (geo:0,0?q=…), "" if none.
function routeQuery(paramsJson) {
    try {
        const p = JSON.parse(paramsJson || "{}");
        return p && p.query ? String(p.query).trim().substring(0, 256) : "";
    } catch (e) {
        return "";
    }
}
