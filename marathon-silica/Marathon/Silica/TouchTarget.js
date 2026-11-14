.pragma library

// The smallest touch target, 7 mm: Apple's 44 pt, Material's 48 dp.
// panelDpi is the shell's DeviceProfile.panelDpi (0 where unknown);
// pixelDensity is Screen.pixelDensity in px/mm, which apps get from the
// panel's wl_output size.
function minimum(panelDpi, pixelDensity) {
    const perMm = panelDpi > 0 ? panelDpi / 25.4 : (pixelDensity > 0 ? pixelDensity : 160 / 25.4);
    return Math.round(7 * perMm);
}

// How far a control `size` px across reaches past each edge to make the minimum.
function pad(size, panelDpi, pixelDensity) {
    return Math.max(0, (minimum(panelDpi, pixelDensity) - size) / 2);
}
