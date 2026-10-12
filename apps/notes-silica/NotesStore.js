.pragma library

function parse(json) {
    try {
        const v = JSON.parse(json);
        return Array.isArray(v) ? v : [];
    } catch (e) {
        return [];
    }
}

function nextId(notes) {
    return notes.reduce((m, n) => Math.max(m, n.id), 0) + 1;
}

function create(notes, title, content, now) {
    const note = { id: nextId(notes), title: title || "Untitled", content: content || "", timestamp: now };
    return [note].concat(notes);
}

function update(notes, id, title, content, now) {
    if (!notes.some(n => n.id === id))
        return notes;
    return notes.map(n => n.id === id ? { id: id, title: title || "Untitled", content: content, timestamp: now } : n);
}

function remove(notes, id) {
    return notes.filter(n => n.id !== id);
}
