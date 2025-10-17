import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property string title: ""
    property alias leftActions: leftActionsContainer.children
    property alias rightActions: rightActionsContainer.children
    property bool showBackButton: false
    
    signal backPressed()
    
    implicitHeight: Constants.actionBarHeight
    color: MElevation.getSurface(2)
    radius: 0
    
    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: 0
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderOuter(2)
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Constants.borderWidthThin
        anchors.bottomMargin: 0
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderInner(2)
    }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingSmall
        anchors.rightMargin: Constants.spacingSmall
        spacing: Constants.spacingMedium
        
        Item {
            id: leftActionsContainer
            width: childrenRect.width
            height: parent.height
            
            MIconButton {
                visible: root.showBackButton && leftActionsContainer.children.length === 1
                anchors.verticalCenter: parent.verticalCenter
                iconName: "arrow-left"
                size: "medium"
                onClicked: root.backPressed()
            }
        }
        
        Text {
            text: root.title
            font.pixelSize: Constants.fontSizeXLarge
            font.weight: Font.DemiBold
            color: MColors.text
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: parent.width - leftActionsContainer.width - rightActionsContainer.width - parent.spacing * 2
        }
        
        Item {
            id: rightActionsContainer
            width: childrenRect.width
            height: parent.height
        }
    }
}

