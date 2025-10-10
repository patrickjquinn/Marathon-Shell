import QtQuick
import "../theme"

Rectangle {
    id: card
    color: "#FFFFFF"
    radius: 8
    border.width: 1
    border.color: "#E0E0E0"
    
    property alias content: contentItem.children
    
    layer.enabled: true
    layer.effect: ShaderEffect {
        property real shadowOpacity: 0.15
    }
    
    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: 2
    }
}

