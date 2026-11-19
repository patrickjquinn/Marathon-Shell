// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Window
import Sailfish.Silica

// Keel's glass: a surface lit from above, its colour taken from what it
// belongs to. Level 1 is a card resting on the ambience, level 2 a control
// on a card or the ambience. A lit control (switched on, primary) fills with
// its tint. One shader pass, no textures.
ShaderEffect {
    id: root

    property int level: 2
    property color tint: Theme.highlightColor
    property bool lit: false
    property bool pressed: false
    property real radius: Math.min(width, height) / 2

    readonly property bool _light: Theme.colorScheme === Theme.DarkOnLight
    readonly property bool _control: level >= 2
    property real _press: pressed ? 1 : 0

    readonly property size size: Qt.size(width, height)
    readonly property real dpr: Screen.devicePixelRatio
    readonly property color bodyTop: _light ? Qt.rgba(1, 1, 1, _control ? 0.6 : 0.45) : Qt.rgba(1, 1, 1, (_control ? 0.24 : 0.09) + 0.06 * _press)
    readonly property color bodyBottom: Qt.rgba(tint.r, tint.g, tint.b, (_control ? (lit ? 0.9 : 0.3) : 0.22) + 0.1 * _press)
    readonly property color glow: Qt.rgba(tint.r, tint.g, tint.b, _control ? (lit ? 0.9 : 0.25) + 0.25 * _press : 0)
    readonly property real glowWidth: _control ? Math.max(2, Math.min(width, height) * 0.08) : 6
    readonly property real rim: _control ? 1 : 0.3

    fragmentShader: "qrc:/qt/qml/Sailfish/Silica/shaders/glasssurface.frag.qsb"

    Behavior on _press {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
}
