pragma ComponentBehavior: Bound

import MarathonOS.Shell
import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0 as Silica

// What lies behind a surface, frosted live: the open app, or the home
// screen, as it is drawn this frame. The shell composites the apps itself,
// so this is a texture read where another Wayland shell would need a
// screen copy across IPC.
//
// The layers are captured at half size over `region`, blurred with the
// dual filter (four halvings, three doublings, frostdown/frostup.frag),
// and drawn at full size by frost.frag, which also tones the colour like
// the ambience, keeps text readable over a white page, and dithers.
// frost.frag samples by screen position, so the frost stays over what it
// frosts while its surface slides or grows. Each step redraws only when
// the one before it changes, and nothing is captured while it is hidden.
Item {
    id: root

    // Bottom to top, the layers behind; each fills the shell from its origin.
    // A plain array, not list<Item>: qmlcachegen (Qt 6.12) compiles a
    // list<Item> binding that kept the first list it read, so a shade made
    // while locked went on frosting the hidden lock screen, all black.
    property var sources: []
    // The part of the shell they are captured over, in its coordinates.
    property rect region: Qt.rect(0, 0, width, height)
    property bool light: false
    // How far towards black (white on a light ambience) it is toned.
    property real tone: 0.62
    property color dim: Silica.Theme.highlightDimmerColor
    property real saturation: 1.35
    // The blur's reach, in texels at each step.
    property real spread: 1.0

    // Off where the GPU is too weak for it (DeviceProfile.liveBlur), on
    // e-paper and in software rendering: the surface lies on the ambience.
    readonly property bool supported: Constants.liveBlur && !MColors.eink && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool running: visible && sources.length > 0 && region.width > 0 && region.height > 0
    readonly property int format: Constants.gpuHdr ? ShaderEffectSource.RGBA16F : ShaderEffectSource.RGBA8

    function levelSize(divisor) {
        return Qt.size(Math.max(1, Math.ceil(region.width / divisor)), Math.max(1, Math.ceil(region.height / divisor)));
    }

    // One step of the blur: `fx` drawn into a texture at its size. Unseen;
    // the next step, or the frost, samples it.
    component Step: ShaderEffectSource {
        id: step

        required property Item input
        required property size size
        property bool up: false

        width: size.width
        height: size.height
        opacity: 0
        sourceItem: root.running ? fx : null
        hideSource: true
        textureSize: size
        format: root.format
        smooth: true

        ShaderEffect {
            id: fx

            readonly property Item source: step.input
            readonly property vector2d texel: Qt.vector2d(root.spread / Math.max(1, step.input.width), root.spread / Math.max(1, step.input.height))

            width: step.width
            height: step.height
            opacity: 0
            blending: false
            fragmentShader: step.up ? "qrc:/marathon/shaders/frostup.frag.qsb" : "qrc:/marathon/shaders/frostdown.frag.qsb"
        }
    }

    // The layers at half size, composed in their order.
    Item {
        id: stack

        readonly property size size: root.levelSize(2)

        width: size.width
        height: size.height
        opacity: 0

        Repeater {
            model: root.sources

            ShaderEffectSource {
                required property Item modelData

                anchors.fill: parent
                sourceItem: root.running ? modelData : null
                sourceRect: root.region
                textureSize: stack.size
                format: root.format
                recursive: false
                smooth: true
            }
        }
    }

    ShaderEffectSource {
        id: capture

        width: stack.width
        height: stack.height
        opacity: 0
        sourceItem: root.running ? stack : null
        hideSource: true
        textureSize: stack.size
        format: root.format
        smooth: true
    }

    Step {
        id: down4
        input: capture
        size: root.levelSize(4)
    }
    Step {
        id: down8
        input: down4
        size: root.levelSize(8)
    }
    Step {
        id: down16
        input: down8
        size: root.levelSize(16)
    }
    Step {
        id: down32
        input: down16
        size: root.levelSize(32)
    }
    Step {
        id: up16
        input: down32
        size: root.levelSize(16)
        up: true
    }
    Step {
        id: up8
        input: up16
        size: root.levelSize(8)
        up: true
    }
    Step {
        id: up4
        input: up8
        size: root.levelSize(4)
        up: true
    }

    // The window's pixels to the frost texture's coordinates: undo the
    // scene's rotation (the compositor turns the shell, not the window),
    // then take the region's place and size out.
    readonly property Item scene: root.Window.contentItem
    readonly property real windowWidth: root.Window.width
    readonly property real windowHeight: root.Window.height
    readonly property int sceneRotation: scene ? Math.round(scene.rotation) % 360 : 0

    ShaderEffect {
        readonly property Item source: up4
        readonly property vector2d viewport: Qt.vector2d(root.windowWidth, root.windowHeight)
        readonly property vector2d texel: Qt.vector2d(root.spread / Math.max(1, up4.width), root.spread / Math.max(1, up4.height))
        readonly property real yUp: GraphicsInfo.api === GraphicsInfo.OpenGL ? 1 : 0
        readonly property real saturation: root.saturation
        readonly property real tone: root.tone
        readonly property real dimAmount: 0.12
        readonly property real light: root.light ? 1 : 0
        // Secondary text keeps 3:1 over the frost (as KeelAmbienceBackground's tone).
        readonly property real knee: root.light ? 0.32 : 0.14
        readonly property real ceiling: root.light ? 0.435 : 0.22
        readonly property color dim: root.dim
        // u = a·x + b·y + c over the window's pixels, as (a, b, c, 0).
        readonly property vector4d mapX: {
            const r = root.region, W = root.windowWidth, H = root.windowHeight;
            switch (root.sceneRotation) {
            case 90:
                return Qt.vector4d(0, 1 / r.width, -r.x / r.width, 0);
            case 180:
                return Qt.vector4d(-1 / r.width, 0, (W - r.x) / r.width, 0);
            case 270:
                return Qt.vector4d(0, -1 / r.width, (H - r.x) / r.width, 0);
            default:
                return Qt.vector4d(1 / r.width, 0, -r.x / r.width, 0);
            }
        }
        readonly property vector4d mapY: {
            const r = root.region, W = root.windowWidth, H = root.windowHeight;
            switch (root.sceneRotation) {
            case 90:
                return Qt.vector4d(-1 / r.height, 0, (W - r.y) / r.height, 0);
            case 180:
                return Qt.vector4d(0, -1 / r.height, (H - r.y) / r.height, 0);
            case 270:
                return Qt.vector4d(1 / r.height, 0, -r.y / r.height, 0);
            default:
                return Qt.vector4d(0, 1 / r.height, -r.y / r.height, 0);
            }
        }

        anchors.fill: parent
        vertexShader: "qrc:/marathon/shaders/frost.vert.qsb"
        fragmentShader: "qrc:/marathon/shaders/frost.frag.qsb"
    }
}
