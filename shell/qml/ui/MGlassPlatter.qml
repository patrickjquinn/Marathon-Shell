import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0 as Silica

// A rounded, frosted glass card with a raised, top-lit rim: the notification
// platter. One shader pass, no per-card blur. `backdrop` is either an
// MGlassBackdrop's texture (screenSpace, the default) or a blur of just the
// area behind this card (screenSpace: false).
ShaderEffect {
    id: root

    property var backdrop: null
    property bool pressed: false
    property bool screenSpaceLookup: true

    property real radius: Silica.Theme.paddingLarge + Silica.Theme.paddingSmall
    property color tint: pressed ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0.13, 0.14, 0.16, 0.30)
    property real rim: 1.0

    readonly property size size: Qt.size(width, height)
    readonly property real screenSpace: screenSpaceLookup ? 1 : 0
    readonly property size screenSize: Qt.size((Window.width || 1) * Screen.devicePixelRatio, (Window.height || 1) * Screen.devicePixelRatio)
    readonly property real flipY: GraphicsInfo.api === GraphicsInfo.OpenGL ? 1 : 0

    visible: backdrop !== null
    fragmentShader: "qrc:/marathon/shaders/glassplatter.frag.qsb"

    Behavior on tint {
        ColorAnimation { duration: 120 }
    }
}
