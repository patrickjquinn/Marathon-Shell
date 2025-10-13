import QtQuick

// Simple icon component that loads Lucide SVG icons
// Note: Color tinting is handled by creating different SVG versions
// The 'color' property is kept for API compatibility but not yet fully implemented
Image {
    id: icon
    property string name: "wifi"
    property color color: "#FFFFFF"
    property int size: 24
    
    width: size
    height: size
    source: name ? "qrc:/images/icons/lucide/" + name + ".svg" : ""
    sourceSize: Qt.size(size, size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    antialiasing: true
    asynchronous: true
    cache: true
    
    // Show placeholder if icon fails to load
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        radius: width / 2
        color: Qt.rgba(icon.color.r, icon.color.g, icon.color.b, 0.2)
        border.width: 1
        border.color: Qt.rgba(icon.color.r, icon.color.g, icon.color.b, 0.4)
        visible: parent.status === Image.Error || parent.status === Image.Null
    }
}

