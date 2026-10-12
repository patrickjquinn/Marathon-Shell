import QtQuick

// Stands in for the viewfinder, which cannot render offscreen.
Rectangle {
    enum FillMode { Stretch, PreserveAspectFit, PreserveAspectCrop }

    property QtObject videoSink: QtObject {}
    property int fillMode: 0

    gradient: Gradient {
        GradientStop { position: 0; color: "#3a5a78" }
        GradientStop { position: 0.6; color: "#8a9a6a" }
        GradientStop { position: 1; color: "#4a3a2a" }
    }
}
