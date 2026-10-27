.pragma library

// The interface sizes Settings offers (apps/settings/SettingsLogic.js), so a
// size chosen in setup is one Settings can show.
const factors = [0.75, 0.9, 1, 1.1, 1.25, 1.4, 1.5];

function nearest(factor) {
    let best = 0;
    for (let i = 1; i < factors.length; ++i)
        if (Math.abs(factors[i] - factor) < Math.abs(factors[best] - factor))
            best = i;
    return best;
}

function label(index) {
    return Math.round(factors[Math.round(index)] * 100) + "%";
}
