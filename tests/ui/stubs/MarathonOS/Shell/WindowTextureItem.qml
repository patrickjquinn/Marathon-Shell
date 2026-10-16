import QtQuick

// Stand-in for the C++ WindowTextureItem: same API, never has a texture, so
// the views it would draw stay visible.
Item {
    property Item source: null
    property real radius: 0
    property rect sourceRect: Qt.rect(0, 0, 1, 1)
    readonly property bool ready: false
}
