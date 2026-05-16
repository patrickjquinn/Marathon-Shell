import MarathonCompositor 1.0
import QtQuick
import QtQuick.Window
import QtWayland.Compositor
import QtWayland.Compositor.XdgShell

// Single-window, single-output Marathon compositor scene.
//
// Phase C-1 ships an empty black scene — the wayland globals are present
// so clients can bind them, but nothing renders yet. Apps that connect
// will hold xdg-shell handles whose surfaces aren't drawn (compositor
// silently accepts the buffers but doesn't show anything). This is
// intentional: C-2 will introduce a real app-surface presenter once the
// shell is a Wayland client itself.
Window {
    id: rootWindow

    width: 540
    height: 1140
    visible: true
    color: "black"
    title: "Marathon Compositor"

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        Text {
            anchors.centerIn: parent
            color: "#444"
            font.family: "monospace"
            font.pixelSize: 12
            text: "marathon-compositor (Phase C-1 scaffold)\n" + "socket: " + MarathonCompositor.socketName + "\n" + "waiting for shell + app clients…"
        }
    }

    // Per-XDG-toplevel rendering will be wired in C-2.
    Repeater {
        model: MarathonCompositor.xdgShell ? MarathonCompositor.xdgShell.shellSurfaces : null
        delegate: WaylandQuickItem {
            anchors.fill: parent
            surface: shellSurface ? shellSurface.surface : null
        }
    }
}
