import QtQuick
import "../Theme"
import "../Core"

Rectangle {
    id: root
    
    property string title: ""
    property bool showBackButton: false
    property string rightIconName: ""
    property alias leftContent: leftContainer.data
    property alias rightContent: rightContainer.data
    
    signal backClicked()
    signal rightIconClicked()
    
    implicitWidth: parent.width
    implicitHeight: 56
    color: MColors.glass
    border.width: 1
    border.color: MColors.glassBorder
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.md
        
        Item {
            id: leftContainer
            width: showBackButton ? 48 : childrenRect.width
            height: parent.height
            
            MIconButton {
                visible: showBackButton && leftContainer.children.length === 1
                iconName: "chevron-left"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.backClicked()
            }
        }
        
        Text {
            text: root.title
            color: MColors.text
            font.pixelSize: MTypography.sizeLarge
            font.weight: MTypography.weightDemiBold
            font.family: MTypography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - leftContainer.width - rightContainer.width - MSpacing.md * 2
            elide: Text.ElideRight
        }
        
        Item {
            id: rightContainer
            width: rightIconName !== "" ? 48 : childrenRect.width
            height: parent.height
            
            MIconButton {
                visible: rightIconName !== "" && rightContainer.children.length === 1
                iconName: rightIconName
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                onClicked: root.rightIconClicked()
            }
        }
    }
}

