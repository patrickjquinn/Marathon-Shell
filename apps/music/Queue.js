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
