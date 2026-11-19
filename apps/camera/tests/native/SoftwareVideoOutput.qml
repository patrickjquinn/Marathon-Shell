import QtQuick

// The viewfinder, which cannot render offscreen.
Rectangle {
    enum FillMode {
        Stretch,
        PreserveAspectFit,
        PreserveAspectCrop
    }

    property int fillMode
    property bool frozen

    color: "#3a5a78"
}
