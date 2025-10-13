import QtQuick
import "../Theme"

Rectangle {
    id: root
    
    default property alias content: contentContainer.data
    
    implicitWidth: parent.width
    implicitHeight: 72
    color: MColors.glass
    border.width: 1
    border.color: MColors.glassBorder
    
    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: MSpacing.md
    }
}

