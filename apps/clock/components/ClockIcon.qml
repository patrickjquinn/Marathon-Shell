import QtQuick

Image {
    id: icon
    property string name: "clock"
    property color color: "#FFFFFF"
    property int size: Constants.iconSizeMedium

    width: size
    height: size
    source: name ? Qt.resolvedUrl("../assets/icons/" + name + ".svg") : ""
    sourceSize: Qt.size(size, size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    cache: true

    // Color filtering disabled - requires Qt 6.5+ MultiEffect or Qt 5.15 ColorOverlay
    // For now, use icon as-is. TODO: Add colorization support for Qt 6.4
    layer.enabled: false
}
