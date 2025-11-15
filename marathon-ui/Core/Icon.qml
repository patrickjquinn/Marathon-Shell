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

    // Qt 6.4: Icon colorization disabled (requires QtQuick.Effects)
}


