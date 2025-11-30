import QtQuick
import Qt5Compat.GraphicalEffects

Image {
    id: root
    property string name: ""
    property color color: MColors.textPrimary
    property int size: 24

    width: size
    height: size
    source: name ? "qrc:/images/icons/lucide/" + name + ".svg" : ""
    // sourceSize: Qt.size(size, size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    cache: true

    // Tinting enabled via Qt5Compat.GraphicalEffects (compatible with Qt 6.x)
    layer.enabled: name !== "" && color !== "transparent"
    layer.effect: ColorOverlay {
        color: root.color
    }
}


