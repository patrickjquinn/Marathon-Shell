import QtQuick
import QtQuick.Effects

Image {
    id: icon
    property string name: "wifi"
    property color color: "#FFFFFF"
    property int size: Constants.iconSizeMedium
    
    width: size
    height: size
    source: name ? "qrc:/images/icons/lucide/" + name + ".svg" : ""
    sourceSize: Qt.size(size, size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    cache: true
    
    layer.enabled: true
    layer.effect: MultiEffect {
        brightness: 1.0
        colorization: 1.0
        colorizationColor: icon.color
    }
}

