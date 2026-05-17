import MarathonCompositor 1.0
import QtQuick
import QtQuick.Window
import QtWayland.Compositor
import QtWayland.Compositor.XdgShell

// Marathon compositor scene. Built around the Qt-blessed pattern for
// standalone QtQuick compositors: the WaylandCompositor IS the root,
// the WaylandOutput is declared as a QML child of the Window with
// `compositor:` and `window:` as set-once bindings honoured during
// componentComplete. Doing this wiring from C++ after the QML engine
// has loaded triggers a threaded-render-loop race that segfaults on
// LLVMpipe/virtio-gpu (see docs/C7_STATUS.md for the rabbit hole).
MarathonCompositor {
    id: comp

    Window {
        id: outputWindow

        width: 540
        height: 1140
        visible: true
        color: "black"
        title: "Marathon Compositor"

        WaylandOutput {
            id: marathonOutput
            compositor: comp
            window: outputWindow
            sizeFollowsWindow: true

            Component.onCompleted: comp.setupOutput(marathonOutput)
        }

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#000000"

                Text {
                    anchors.centerIn: parent
                    color: "#444"
                    font.family: "monospace"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    text: "marathon-compositor\n" + "socket: " + comp.socketName + "\n" + "waiting for shell + app clients…"
                }
            }

            // Per-xdg-toplevel rendering. Uses ShellSurfaceItem (the
            // QWaylandQuickShellSurfaceItem subclass that handles
            // surface destruction + focus + popups) rather than raw
            // WaylandQuickItem — the bare item leaks a render-thread
            // null-deref when shellSurface goes null.
            Repeater {
                model: comp.xdgShell ? comp.xdgShell.shellSurfaces : null
                delegate: ShellSurfaceItem {
                    anchors.fill: parent
                    shellSurface: model.shellSurface
                    onSurfaceDestroyed: destroy()
                }
            }
        }
    }
}
