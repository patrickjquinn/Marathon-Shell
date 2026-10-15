import QtQuick
import Sailfish.Silica as S

S.ApplicationWindow {
    id: root

    property string appId: ""

    signal minimizeRequested

    // A combo box's or list item's menu is not among its children.
    function _openMenu(item) {
        for (const menu of [item.menu, item._menuItem]) {
            if (menu && menu.hasOwnProperty("_keyboardReturnFocus") && menu.active)
                return menu;
        }
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const menu = root._openMenu(children[i]);
            if (menu)
                return menu;
        }
        return null;
    }

    // Called by the app runner for the system back gesture. An open menu
    // closes first: popping would discard a dialog's whole form.
    function handleBack() {
        const menu = root.pageStack.currentPage ? root._openMenu(root.pageStack.currentPage) : null;
        if (menu) {
            menu.close();
            return true;
        }
        if (root.pageStack.depth > 1) {
            root.pageStack.pop();
            return true;
        }
        root.minimizeRequested();
        return true;
    }

}
