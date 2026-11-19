// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Window
import Sailfish.Silica

// Keel's glass: the surface of a container (a card, a tile, a panel), never
// of the controls inside it, which stay flat. Its colour comes from what it
// belongs to: `tint` is the ambience highlight unless the container has its
// own. A lit container (a switched-on tile) fills with the tint. One shader
// pass, no textures.
ShaderEffect {
    id: root

    property color tint: Theme.highlightColor
    property bool lit: false
    property bool pressed: false
    property real radius: Theme.paddingMedium

    readonly property bool _light: Theme.colorScheme === Theme.DarkOnLight
    property real _press: pressed ? 1 : 0

    readonly property size size: Qt.size(width, height)
    readonly property real dpr: Screen.devicePixelRatio
    readonly property color bodyTop: lit ? Qt.rgba(tint.r, tint.g, tint.b, 0.55 + 0.1 * _press) : _light ? Qt.rgba(1, 1, 1, 0.5 + 0.1 * _press) : Qt.rgba(1, 1, 1, 0.09 + 0.06 * _press)
    readonly property color bodyBottom: Qt.rgba(tint.r, tint.g, tint.b, (lit ? 0.42 : 0.08) + 0.1 * _press)
    readonly property real edgeLight: lit ? 0.22 : 0.16
    readonly property real edgeShade: _light ? 0.12 : 0.35

    fragmentShader: "qrc:/qt/qml/Sailfish/Silica/shaders/glasssurface.frag.qsb"

    Behavior on _press {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
}
