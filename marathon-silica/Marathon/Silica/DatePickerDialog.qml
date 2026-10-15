import QtQuick
import Sailfish.Silica as S

S.DatePickerDialog {
    id: root

    function _find(item, test) {
        if (test(item))
            return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const found = _find(children[i], test);
            if (found)
                return found;
        }
        return null;
    }

    // Keel sizes the scroll area to the date label above the grid, so on a
    // short screen the last weeks of the month can't be scrolled to.
    function _reachGrid() {
        const flick = _find(root, i => i.selectedDateText !== undefined);
        const grid = flick ? _find(flick.contentItem, i => i.cellHeight !== undefined && i.weeksVisible !== undefined) : null;
        if (grid)
            flick.contentHeight = Qt.binding(() => Math.max(grid.y + grid.height + S.Theme.paddingLarge, flick.height));
    }

    Component.onCompleted: _reachGrid()
    onStatusChanged: if (status === S.PageStatus.Activating) _reachGrid()

    DialogHeaderBackdrop {
        header: root._dialogHeader
    }
}
