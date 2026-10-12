.pragma library

function items(menu) {
    const found = [];
    function walk(item) {
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (!child.visible)
                continue;
            if (child.hasOwnProperty("__silica_menuitem")) {
                if (child.enabled)
                    found.push(child);
            } else {
                walk(child);
            }
        }
    }
    walk(menu._contentColumn);
    found.sort(function (a, b) { return a.mapToItem(menu, 0, 0).y - b.mapToItem(menu, 0, 0).y; });
    return found;
}

function open(menu, returnFocus) {
    menu._keyboardReturnFocus = returnFocus;
    menu.active = true;
    menu.flickable.contentY = menu._finalPosition;
    menu.forceActiveFocus();
}

function highlight(menu, item) {
    const p = item.mapToItem(menu._contentColumn, item.width / 2, item.height / 2);
    menu._highlightMenuItem(menu._contentColumn, p.y);
}

function step(menu, delta) {
    const list = items(menu);
    if (list.length === 0)
        return;
    const at = list.indexOf(menu.menuItem);
    const next = at < 0 ? (delta > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, at + delta));
    highlight(menu, list[next]);
}

function close(menu) {
    const back = menu._keyboardReturnFocus;
    menu._keyboardReturnFocus = null;
    menu.close();
    if (back)
        back.forceActiveFocus();
}

function handleKey(menu, event) {
    switch (event.key) {
    case Qt.Key_Down: step(menu, 1); break;
    case Qt.Key_Up: step(menu, -1); break;
    case Qt.Key_Return:
    case Qt.Key_Enter:
    case Qt.Key_Space: {
        const item = menu.menuItem;
        close(menu);
        if (item)
            item.clicked();
        break;
    }
    case Qt.Key_Escape: close(menu); break;
    default: return;
    }
    event.accepted = true;
}
