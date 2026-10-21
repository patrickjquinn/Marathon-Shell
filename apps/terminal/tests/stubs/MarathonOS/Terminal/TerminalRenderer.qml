import QtQuick

Item {
    property var terminal
    property font font
    property real charWidth: 10
    property real charHeight: 20
    property color textColor
    property color backgroundColor
    property color selectionColor
    property real scrollOffset
    property int historyLines
    property var selected: null

    signal charSizeChanged
    signal textCommitted(string text)

    function select(sx, sy, ex, ey) {
        selected = [sx, sy, ex, ey];
    }
    function clearSelection() {
        selected = null;
    }
    function selectedText() {
        return selected ? "selected" : "";
    }
    function positionToGrid(x, y) {
        return Qt.point(Math.floor(x / charWidth), Math.floor(y / charHeight));
    }
}
