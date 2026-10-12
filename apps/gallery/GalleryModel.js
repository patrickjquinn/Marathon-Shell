.pragma library

function fileName(item) {
    if (!item || !item.path)
        return "";
    return decodeURIComponent(String(item.path).split("/").pop());
}

function filter(photos, query) {
    const q = (query || "").trim().toLowerCase();
    if (q.length === 0)
        return photos;
    return photos.filter(p => {
        const date = p.timestamp ? Qt.formatDate(new Date(p.timestamp), "d MMMM yyyy") : "";
        return (fileName(p) + " " + (p.album || "") + " " + date).toLowerCase().indexOf(q) >= 0;
    });
}

function albumPhotos(photos, albumId) {
    return photos.filter(p => p.album === albumId);
}

// Anniversary throwbacks: media whose calendar day is within three days of
// today's in an earlier year, one cluster per year back, nearest first.
function memoryClusters(photos, videos, now) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const buckets = {};
    const order = [];
    const consider = (item, isVideo) => {
        if (!item || !item.timestamp)
            return;
        const ts = new Date(item.timestamp);
        const years = now.getFullYear() - ts.getFullYear();
        if (years < 1)
            return;
        const probe = new Date(now.getFullYear(), ts.getMonth(), ts.getDate());
        if (Math.abs((probe - today) / 86400000) > 3)
            return;
        const key = "y" + years;
        if (!buckets[key]) {
            buckets[key] = { years: years, photos: [], videoCount: 0 };
            order.push(key);
        }
        if (isVideo)
            buckets[key].videoCount++;
        else
            buckets[key].photos.push(item);
    };
    photos.forEach(p => consider(p, false));
    videos.forEach(v => consider(v, true));
    order.sort((a, b) => buckets[a].years - buckets[b].years);
    return order.map(k => buckets[k]);
}

function memoryPhotos(memories, years) {
    const m = memories.find(c => c.years === years);
    return m ? m.photos : [];
}

// The main page's rows: all photos, then memories, then albums.
function collections(photos, albums, memories) {
    if (photos.length === 0)
        return [];
    const rows = [{ kind: "all", section: "", count: photos.length, cover: photos[0] }];
    memories.forEach(m => rows.push({
        kind: "memory", section: "memories", years: m.years,
        count: m.photos.length, videoCount: m.videoCount, cover: m.photos[0] || null
    }));
    albums.forEach(a => rows.push({
        kind: "album", section: "albums", albumId: a.id, name: a.name,
        count: a.photoCount, cover: photos.find(p => p.album === a.id) || null
    }));
    return rows;
}

// A random photo for the cover, other than the one shown now when possible.
function pickRandom(photos, current, random) {
    if (photos.length === 0)
        return null;
    const pool = photos.length > 1 && current ? photos.filter(p => p.id !== current.id) : photos;
    return pool[Math.min(pool.length - 1, Math.floor(random * pool.length))];
}

function withoutId(photos, id) {
    return photos.filter(p => p.id !== id);
}
