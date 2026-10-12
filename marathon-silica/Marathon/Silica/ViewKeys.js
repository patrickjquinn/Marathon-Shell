.pragma library

function isMenuKey(event) {
    return event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))
        || (event.key === Qt.Key_M && (event.modifiers & Qt.ControlModifier));
}

// Ctrl+M / Menu opens the push-up menu at the end of the content, otherwise the pull-down menu.
function openPulley(view, event) {
    if (!isMenuKey(event))
        return false;
    const menu = view.pushUpMenu && view.atYEnd && !view.atYBeginning ? view.pushUpMenu
               : view.pullDownMenu ? view.pullDownMenu : view.pushUpMenu;
    if (!menu || !menu.openFromKeyboard || !menu.enabled || !menu.visible)
        return false;
    menu.openFromKeyboard(view);
    event.accepted = true;
    return true;
}

function scrollTo(view, y) {
    const top = view.originY;
    const bottom = view.originY + Math.max(0, view.contentHeight - view.height);
    view.contentY = Math.max(top, Math.min(bottom, y));
}
