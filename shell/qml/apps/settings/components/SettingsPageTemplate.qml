import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Page {
    id: pageTemplate
    
    property string pageTitle: "Settings"
    property alias content: contentLoader.sourceComponent
    property bool showBackButton: true
    
    signal navigateBack()
    
    background: Rectangle {
        color: Colors.backgroundDark
    }
    
    // Header with back button (BB10 style)
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Constants.actionBarHeight
        color: Colors.surface
        z: 10
        visible: showBackButton
        
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Constants.spacingMedium
            anchors.verticalCenter: parent.verticalCenter
            spacing: Constants.spacingMedium
            
            Icon {
                name: "chevron-down"
                size: Constants.iconSizeMedium
                color: Colors.text
                anchors.verticalCenter: parent.verticalCenter
                rotation: 90
            }
            
            Text {
                text: pageTemplate.pageTitle
                color: Colors.text
                font.pixelSize: Typography.sizeBody
                font.weight: Font.DemiBold
                font.family: Typography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                HapticService.light()
                pageTemplate.navigateBack()
            }
            
            // Press feedback
            Rectangle {
                anchors.fill: parent
                color: Colors.text
                opacity: parent.pressed ? 0.1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }
        }
        
        // Bottom border
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(255, 255, 255, 0.08)
        }
    }
    
    // Content area
    Loader {
        id: contentLoader
        anchors.top: showBackButton ? header.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}

