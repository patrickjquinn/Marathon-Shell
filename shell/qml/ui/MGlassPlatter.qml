import QtQuick
import QtQuick.Window
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Marathon glass: the ambience, frosted and tinted, behind a surface with
// the system's two-hairline edge (dark outside, lit inside). One shader
// pass, no per-card blur. `backdrop` is either an
// MGlassBackdrop's texture (screenSpace, the default) or a blur of just the
// area behind this card (screenSpace: false).
ShaderEffect {
    id: root

    property var backdrop: null
    property bool pressed: false
    property bool screenSpaceLookup: true

    property real radius: Silica.Theme.paddingSmall
    property color tint: pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, 0.45) : Silica.Theme.rgba(Silica.Theme.highlightDimmerColor, restAlpha)
    // Deep enough that secondary text (#bababa) keeps 4.5:1 over the
    // wallpaper's brightest spot: the shader mixes in sRGB, and the glass
    // must stay under 0.294 there.
    readonly property real restAlpha: {
        const l = AmbienceService ? AmbienceService.brightest : 0;
        const backdrop = l <= 0.0031308 ? 12.92 * l : 1.055 * Math.pow(l, 1 / 2.4) - 0.055;
        const t = Silica.Theme.highlightDimmerColor;
        const ink = Math.max(t.r, t.g, t.b);
        const needed = backdrop > 0.294 ? (backdrop - 0.294) / Math.max(0.01, backdrop - ink) : 0;
        return Math.min(0.9, Math.max(0.55, needed));
    }
    property real rim: 1.0

    readonly property size size: Qt.size(width, height)
    readonly property real screenSpace: screenSpaceLookup ? 1 : 0
    readonly property size screenSize: Qt.size((Window.width || 1) * Screen.devicePixelRatio, (Window.height || 1) * Screen.devicePixelRatio)
    readonly property real flipY: GraphicsInfo.api === GraphicsInfo.OpenGL ? 1 : 0

    visible: backdrop !== null
    fragmentShader: "qrc:/marathon/shaders/glassplatter.frag.qsb"

    Behavior on tint {
        ColorAnimation {
            duration: 120
        }
    }
}
