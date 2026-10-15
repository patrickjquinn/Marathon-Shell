.pragma library

// Columns by width in Silica units (screen pixels / pixel ratio): five across
// phones, one per 135 units on wide screens, fewer where a large interface
// size leaves a column too narrow for "Calculator" at Theme.fontSizeTiny.
// The pager and the grid pages share it.
function columns(screenWidth, pixelRatio, forcedColumns) {
    if (forcedColumns > 0)
        return forcedColumns;
    const width = screenWidth / pixelRatio;
    if (width < 420)
        return 3;
    if (width < 510)
        return 4;
    return Math.max(5, Math.floor(width / 135));
}

function rows(screenHeight, iconSize) {
    return Math.max(3, Math.round(screenHeight * 0.75 / (iconSize * 1.5 * 1.4)));
}

function pageCount(appCount, itemsPerPage) {
    return Math.max(1, Math.ceil(appCount / itemsPerPage));
}
