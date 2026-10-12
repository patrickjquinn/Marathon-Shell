.pragma library

function isActivationKey(event) {
    return event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space;
}

// Opens a list item's context menu; Ctrl+M is left for the page's pulley menu.
function isMenuKey(event) {
    return event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier));
}

// "image://theme/icon-m-delete?#fff" -> "delete"
function iconName(source) {
    const s = String(source || "");
    const base = s.substring(s.lastIndexOf("/") + 1).split("?")[0].split(".")[0];
    return base.replace(/^icon-[a-z]+-/, "").replace(/-/g, " ");
}
