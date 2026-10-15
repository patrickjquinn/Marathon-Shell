import QtQuick
import Sailfish.Silica as S
import "PulleyKeys.js" as PulleyKeys

S.PullDownMenu {
    id: root

    property Item _keyboardReturnFocus

    // Closed, the indicator borders the shell's bars, not the screen edge.
    highlightColor: active ? palette.highlightBackgroundColor
                           : S.Theme.rgba(palette.highlightBackgroundColor, S.Theme.highlightBackgroundOpacity || 0.3)

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
