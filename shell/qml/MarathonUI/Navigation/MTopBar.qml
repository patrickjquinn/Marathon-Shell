import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
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
        anchors.leftMargin: Constants.spacingMedium
        anchors.rightMargin: Constants.spacingMedium
        spacing: Constants.spacingMedium
        
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
            font.pixelSize: Constants.fontSizeLarge
            font.weight: Font.DemiBold
            font.family: MTypography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - leftContainer.width - rightContainer.width - Constants.spacingMedium * 2
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

