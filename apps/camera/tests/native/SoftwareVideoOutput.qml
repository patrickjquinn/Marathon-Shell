import QtQuick

// The viewfinder, which cannot render offscreen.
Rectangle {
    enum FillMode {
        Stretch,
        PreserveAspectFit,
        PreserveAspectCrop
    }

    readonly property QtObject videoSink: QtObject {}
    property int fillMode

    color: "#3a5a78"
}
