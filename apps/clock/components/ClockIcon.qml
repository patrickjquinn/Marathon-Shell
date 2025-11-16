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
    
    layer.enabled: true
    layer.effect: Item { // MultiEffect disabled for Qt 6.4
        brightness: 1.0
        colorization: 1.0
        colorizationColor: icon.color
    }
}

