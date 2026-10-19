.pragma library

// The release speed from the content's last 100 ms of motion, fitted by
// least squares as Android's VelocityTracker does. Qt's estimate (a Kalman
// filter per touch event, then the mean of the last three) still lags the
// finger at the end of a short fling.

function add(samples, x, y) {
    const t = Date.now();
    samples.push([t, x, y]);
    while (samples.length > 2 && t - samples[0][0] > 100)
        samples.shift();
}

// px/s along coordinate 1 (x) or 2 (y); 0 without enough motion.
function rate(samples, axis) {
    const n = samples.length;
    if (n < 3)
        return 0;
    let mt = 0, mp = 0;
    for (const s of samples) {
        mt += s[0];
        mp += s[axis];
    }
    mt /= n;
    mp /= n;
    let num = 0, den = 0;
    for (const s of samples) {
        num += (s[0] - mt) * (s[axis] - mp);
        den += (s[0] - mt) * (s[0] - mt);
    }
    return den > 0 ? num / den * 1000 : 0;
}
