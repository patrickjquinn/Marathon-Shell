.pragma library

// The low-battery warning bands: 20 %, 10 %, 5 %; 101 above them.
function band(level) {
    return level <= 5 ? 5 : level <= 10 ? 10 : level <= 20 ? 20 : 101;
}

// The band to warn about for a new level, or 0. `state` is {warnedAt, last}
// and is updated. A rising level only moves the bar, whatever the plug state
// says: some gauges report "Unknown", and UPower then flips between charging
// and discharging with every percent gained. It re-arms a band only 3 % clear
// of it, so jitter at an edge stays quiet.
function check(state, level, pluggedIn) {
    const rising = state.last > 0 && level > state.last;
    state.last = level;
    const b = band(level);
    if (rising) {
        state.warnedAt = Math.max(state.warnedAt, band(level - 3));
        return 0;
    }
    if (pluggedIn || level <= 0 || b === 101 || b >= state.warnedAt)
        return 0;
    state.warnedAt = b;
    return b;
}
