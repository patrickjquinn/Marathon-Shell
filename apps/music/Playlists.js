.pragma library

// Playlists hold track paths: the library's track ids change on a rescan.
function parse(json) {
    try {
        const list = JSON.parse(json);
        return Array.isArray(list) ? list : [];
    } catch (e) {
        return [];
    }
}

function create(list, name) {
    const id = list.reduce((max, p) => Math.max(max, p.id), 0) + 1;
    return list.concat([{ id: id, name: name, paths: [] }]);
}

function remove(list, id) {
    return list.filter(p => p.id !== id);
}

function edit(list, id, change) {
    return list.map(p => p.id === id ? { id: p.id, name: p.name, paths: change(p.paths) } : p);
}

function addTrack(list, id, path) {
    return edit(list, id, paths => paths.includes(path) ? paths : paths.concat([path]));
}

function removeTrack(list, id, path) {
    return edit(list, id, paths => paths.filter(p => p !== path));
}

function tracksOf(playlist, tracks) {
    const byPath = {};
    for (const t of tracks)
        byPath[t.path] = t;
    return playlist.paths.filter(p => byPath[p] !== undefined).map(p => byPath[p]);
}
