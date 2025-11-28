import QtQuick
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

    // Tinting disabled due to missing QtQuick.Effects/Qt5Compat.GraphicalEffects and qsb tool
    layer.enabled: false
    // layer.effect: ShaderEffect { ... } removed
}


