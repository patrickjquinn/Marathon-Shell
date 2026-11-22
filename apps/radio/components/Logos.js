.pragma library

// Logos that failed to load this session: a list scrolling past a station
// fetches its broken logo once, not once per tile.
const failed = new Set();

function usable(url) {
    return url.indexOf("http") === 0 && !failed.has(url);
}

function fail(url) {
    failed.add(url);
}
