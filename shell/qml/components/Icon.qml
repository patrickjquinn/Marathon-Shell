import QtQuick

Image {
    id: icon
    property string name: "wifi"
    property color color: "#FFFFFF"
    property int size: 24
    
    width: size
    height: size
    source: "qrc:/images/icons/lucide/" + icon.name + ".svg"
    sourceSize: Qt.size(icon.size, icon.size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    antialiasing: true
}

