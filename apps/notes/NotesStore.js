.pragma library

const taskLine = /^(\s*[-*]?\s*\[)([ xX])(\]\s*(.+))$/;

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

// The first non-blank line names the note.
function titleOf(content) {
    const line = String(content || "").split("\n").find(l => l.trim() !== "");
    return line ? line.trim() : "";
}

// Older notes kept the title apart from the body, and stored "Untitled" for none.
function text(note) {
    const body = String(note.content || "");
    const title = String(note.title || "");
    return title === "" || title === "Untitled" || titleOf(body) === title ? body : title + (body ? "\n" + body : "");
}

// The text after the title line, on one line.
function preview(note) {
    const lines = text(note).split("\n");
    const first = lines.findIndex(l => l.trim() !== "");
    return lines.slice(first + 1).join(" ").replace(/\s+/g, " ").trim();
}

// Today's notes by time; older ones by day and month ("5 Oct"), with the
// year once it is not this one.
function when(timestamp, now) {
    const d = new Date(timestamp);
    if (d.toDateString() === now.toDateString())
        return d.toLocaleTimeString(Qt.locale(), 1); // Locale.ShortFormat; the enum isn't visible here
    return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
}

function create(notes, content, now) {
    const note = { id: nextId(notes), title: titleOf(content), content: content || "", timestamp: now };
    return [note].concat(notes);
}

function edit(notes, id, change) {
    if (!notes.some(n => n.id === id))
        return notes;
    return notes.map(n => n.id === id ? Object.assign({}, n, change) : n);
}

function update(notes, id, content, now) {
    return edit(notes, id, { title: titleOf(content), content: content, timestamp: now });
}

function remove(notes, id) {
    return notes.filter(n => n.id !== id);
}

function setPinned(notes, id, pinned) {
    return edit(notes, id, { pinned: pinned });
}

function sorted(notes) {
    return notes.slice().sort((a, b) => (b.pinned === true) - (a.pinned === true) || b.timestamp - a.timestamp);
}

function search(notes, query) {
    const q = (query || "").trim().toLowerCase();
    if (q === "")
        return notes;
    return notes.filter(n => String(n.title).toLowerCase().includes(q) || String(n.content).toLowerCase().includes(q));
}

// An explicit tag wins; otherwise the first #hashtag in the text.
function tagOf(note) {
    if (note.tag)
        return String(note.tag);
    const m = String(note.content || "").match(/(?:^|\s)#([\w-]+)/);
    return m ? m[1] : "";
}

function folders(notes) {
    const counts = {};
    for (const n of notes) {
        const t = tagOf(n);
        counts[t] = (counts[t] || 0) + 1;
    }
    return Object.keys(counts).sort((a, b) => (a === "") - (b === "") || a.localeCompare(b)).map(t => ({ tag: t, count: counts[t] }));
}

function inFolder(notes, tag) {
    return notes.filter(n => tagOf(n) === tag);
}

function tasks(notes) {
    const out = [];
    for (const n of notes) {
        const lines = String(n.content || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(taskLine);
            if (m)
                out.push({ noteId: n.id, noteTitle: n.title || "", line: i, checked: m[2] !== " ", text: m[4].trim() });
        }
    }
    return out;
}

function toggleTask(notes, id, line, now) {
    const note = notes.find(n => n.id === id);
    if (!note)
        return notes;
    const lines = String(note.content || "").split("\n");
    const m = line >= 0 && line < lines.length ? lines[line].match(taskLine) : null;
    if (!m)
        return notes;
    lines[line] = m[1] + (m[2] === " " ? "x" : " ") + m[3];
    return edit(notes, id, { content: lines.join("\n"), timestamp: now });
}

// Appends notes from the pre-Keel store, renumbering ids that clash.
function merge(current, legacy) {
    const out = current.slice();
    const taken = new Set(current.map(n => n.id));
    for (const old of legacy) {
        if (!old || typeof old !== "object")
            continue;
        const note = Object.assign({}, old, {
            title: old.title || "",
            content: old.content ? String(old.content) : "",
            timestamp: Number(old.timestamp) || 0
        });
        if (typeof note.id !== "number" || taken.has(note.id))
            note.id = nextId(out);
        taken.add(note.id);
        out.push(note);
    }
    return out;
}

// A share's text (Sailfish.Share resources): a link keeps its title above it.
function sharedText(resources) {
    return (resources || []).map(r => {
        const data = String(r.data || "");
        const name = String(r.name || "");
        return data === "" ? "" : name !== "" && name !== data ? name + "\n" + data : data;
    }).filter(t => t !== "").join("\n\n");
}
