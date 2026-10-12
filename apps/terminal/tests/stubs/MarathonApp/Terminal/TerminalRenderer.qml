import QtQuick

Item {
    property var terminal
    property font font
    property real charWidth: 10
    property real charHeight: 20
    property color textColor
    property color backgroundColor
    property color selectionColor
    property var selected: null

    signal charSizeChanged

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
