.pragma library

// Index to play after `index`, or -1 to stop. `random` is in [0, 1).
function next(count, index, shuffle, wrap, random) {
    if (count === 0)
        return -1;
    if (shuffle) {
        if (count === 1)
            return 0;
        const pick = Math.floor(random * (count - 1));
        return pick >= index ? pick + 1 : pick;
    }
    if (index + 1 < count)
        return index + 1;
    return wrap ? 0 : -1;
}

function previous(count, index) {
    return count === 0 ? -1 : (index - 1 + count) % count;
}

// A shuffled copy of `list`; `random()` returns values in [0, 1).
function shuffled(list, random) {
    const out = list.slice();
    for (let i = out.length - 1; i > 0; --i) {
        const j = Math.floor(random() * (i + 1));
        const t = out[i];
        out[i] = out[j];
        out[j] = t;
    }
    return out;
}
