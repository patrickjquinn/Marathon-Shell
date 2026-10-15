.pragma library

// As many columns as the launcher icon fits with room for its label, and rows
// to match. The pager and the grid pages share it.
function columns(screenWidth, iconSize, forcedColumns) {
    return forcedColumns > 0 ? forcedColumns : Math.max(3, Math.floor(screenWidth / (iconSize * 1.23)));
}

function rows(screenHeight, iconSize) {
    return Math.max(3, Math.round(screenHeight * 0.75 / (iconSize * 1.5 * 1.4)));
}

function pageCount(appCount, itemsPerPage) {
    return Math.max(1, Math.ceil(appCount / itemsPerPage));
}
