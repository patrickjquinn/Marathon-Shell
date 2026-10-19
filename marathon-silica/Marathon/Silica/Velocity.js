.pragma library

// The release speed from the content's last 50 ms of motion (at least three
// samples), fitted by least squares; Pacific's engine measures over 50 ms.
// Qt's estimate (a Kalman filter per touch event, then the mean of the last
// three) lags the finger at the end of a short fling.

function add(samples, x, y) {
    const t = Date.now();
    samples.push([t, x, y]);
    while (samples.length > 3 && t - samples[0][0] > 50)
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
