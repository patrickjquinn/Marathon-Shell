import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

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
        anchors.margins: Constants.spacingMedium
    }
}

