import QtQuick
import Sailfish.Silica as S
import "PulleyKeys.js" as PulleyKeys

S.PullDownMenu {
    id: root

    property Item _keyboardReturnFocus

    function openFromKeyboard(returnFocus) {
        PulleyKeys.open(root, returnFocus);
    }

    // A menu opened from the keyboard closes when focus moves elsewhere.
    onActiveFocusChanged: {
        if (!activeFocus && active && _keyboardReturnFocus) {
            _keyboardReturnFocus = null;
            close();
        }
    }

    Accessible.role: Accessible.PopupMenu
    Keys.onPressed: function (event) { PulleyKeys.handleKey(root, event); }
}
