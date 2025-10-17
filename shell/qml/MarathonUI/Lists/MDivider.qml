import QtQuick
import MarathonUI.Theme

Rectangle {
    id: root
    
    property string orientation: "horizontal"
    
    implicitWidth: orientation === "horizontal" ? parent.width : 1
    implicitHeight: orientation === "horizontal" ? 1 : parent.height
    color: MColors.border
}

