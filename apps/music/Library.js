.pragma library

function formatTime(seconds) {
    const s = isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
    const secs = s % 60;
    return Math.floor(s / 60) + ":" + (secs < 10 ? "0" : "") + secs;
}

function byName(a, b) {
    return a.name.localeCompare(b.name);
}

function artists(tracks) {
    const groups = {};
    for (const t of tracks) {
        const g = groups[t.artist] || (groups[t.artist] = { name: t.artist, albums: {}, trackCount: 0 });
        g.albums[t.album] = true;
        g.trackCount++;
    }
    return Object.keys(groups).map(k => ({
        name: groups[k].name,
        albumCount: Object.keys(groups[k].albums).length,
        trackCount: groups[k].trackCount
    })).sort(byName);
}

// An album shared by several artists (a compilation) gets artist "".
function albums(tracks, artist) {
    const groups = {};
    for (const t of tracks) {
        if (artist !== undefined && t.artist !== artist)
            continue;
        const g = groups[t.album];
        if (!g)
            groups[t.album] = { name: t.album, artist: t.artist, trackCount: 1 };
        else {
            g.trackCount++;
            if (g.artist !== t.artist)
                g.artist = "";
        }
    }
    return Object.keys(groups).map(k => groups[k]).sort(byName);
}

function albumTracks(tracks, album, artist) {
    return tracks.filter(t => t.album === album && (artist === undefined || t.artist === artist))
        .sort((a, b) => (a.trackNumber - b.trackNumber) || a.title.localeCompare(b.title));
}

function songs(tracks) {
    return tracks.slice().sort((a, b) => a.title.localeCompare(b.title));
}

function search(tracks, query) {
    const q = query.trim().toLowerCase();
    if (q === "")
        return [];
    return songs(tracks.filter(t => t.title.toLowerCase().includes(q) || t.artist.toLowerCase().includes(q)
                               || t.album.toLowerCase().includes(q)));
}
