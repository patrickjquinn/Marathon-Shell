import QtQuick
import "../../theme"

Row {
    id: pageIndicator
    spacing: Constants.spacingMedium
    
    property int currentPage: 0
    property int totalPages: 1
    property bool showHubIcon: false
    property bool showTaskSwitcherIcon: false
    
    signal hubClicked()
    signal taskSwitcherClicked()
    
    Rectangle {
        visible: showHubIcon
        width: 32
        height: 32
        radius: 4
        color: currentPage === -2 ? "#FFFFFF" : "#666666"
        
        Image {
            source: "qrc:/images/icons/lucide/bell.svg"
            width: 18
            height: 18
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: hubClicked()
        }
    }
    
    Rectangle {
        visible: showTaskSwitcherIcon
        width: 32
        height: 32
        radius: 4
        color: currentPage === -1 ? "#FFFFFF" : "#666666"
        
        Image {
            source: "qrc:/images/icons/lucide/grid.svg"
            width: 18
            height: 18
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: taskSwitcherClicked()
        }
    }
    
    Repeater {
        model: totalPages
        
        Rectangle {
            width: 8
            height: 8
            radius: 4
            color: index === currentPage ? "#FFFFFF" : "#666666"
            anchors.verticalCenter: parent.verticalCenter
            
            Behavior on color {
                ColorAnimation { duration: 200 }
            }
        }
    }
}

