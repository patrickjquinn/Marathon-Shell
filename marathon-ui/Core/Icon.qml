import QtQuick
import QtQuick.Effects
import MarathonUI.Theme

Image {
    id: root
    property string name: ""
    property color color: MColors.textPrimary
    property int size: 24

    width: size
    height: size
    source: name ? "qrc:/images/icons/lucide/" + name + ".svg" : ""
    sourceSize: Qt.size(size, size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    cache: true

    // Tint the SVG to the specified color
    layer.enabled: true
    layer.effect: MultiEffect {
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.color
    }
}
