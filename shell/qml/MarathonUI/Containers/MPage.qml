import QtQuick
import QtQuick.Controls
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root
    
    property string title: ""
    property bool showBackButton: false
    property alias contentItem: scrollView.contentItem
    property alias content: contentContainer.data
    property bool showTopBar: true
    property bool showBottomBar: false
    property alias bottomBarContent: bottomBarContainer.data
    
    signal backClicked()
    
    color: MColors.background
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Rectangle {
            id: topBar
            visible: showTopBar
            width: parent.width
            height: 56
            color: MColors.glass
            border.width: 1
            border.color: MColors.glassBorder
            z: 100
            
            Row {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingMedium
                anchors.rightMargin: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                Icon {
                    visible: showBackButton
                    name: "chevron-left"
                    size: Constants.iconSizeMedium
                    color: MColors.text
                    anchors.verticalCenter: parent.verticalCenter
                    
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
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
                }
            }
        }
        
        Flickable {
            id: scrollView
            width: parent.width
            height: parent.height - (showTopBar ? 56 : 0) - (showBottomBar ? 72 : 0)
            contentHeight: contentContainer.height
            clip: true
            
            flickDeceleration: 5000
            maximumFlickVelocity: 2500
            
            Column {
                id: contentContainer
                width: parent.width
            }
        }
        
        Rectangle {
            id: bottomBar
            visible: showBottomBar
            width: parent.width
            height: Constants.appIconSize
            color: MColors.glass
            border.width: 1
            border.color: MColors.glassBorder
            z: 100
            
            Item {
                id: bottomBarContainer
                anchors.fill: parent
                anchors.margins: Constants.spacingMedium
            }
        }
    }
}

