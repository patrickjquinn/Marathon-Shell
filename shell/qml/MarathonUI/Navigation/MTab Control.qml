import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell

Rectangle {
    id: root
    
    property int currentIndex: 0
    property var tabs: []
    property alias content: stackLayout.children
    property string orientation: "horizontal"
    
    signal tabChanged(int index)
    
    implicitWidth: 300
    implicitHeight: orientation === "horizontal" ? 
        Constants.actionBarHeight + stackLayout.implicitHeight :
        600
    
    color: MElevation.getSurface(1)
    radius: 0
    
    RowLayout {
        anchors.fill: parent
        spacing: 0
        
        Rectangle {
            id: tabBar
            Layout.fillWidth: root.orientation === "horizontal"
            Layout.fillHeight: root.orientation === "vertical"
            Layout.preferredHeight: root.orientation === "horizontal" ? Constants.actionBarHeight : parent.height
            Layout.preferredWidth: root.orientation === "vertical" ? Constants.touchTargetLarge * 2 : parent.width
            
            color: MElevation.getSurface(2)
            
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: Constants.borderWidthThin
                border.color: MElevation.getBorderOuter(2)
            }
            
            Rectangle {
                anchors.fill: parent
                anchors.margins: Constants.borderWidthThin
                color: "transparent"
                border.width: Constants.borderWidthThin
                border.color: MElevation.getBorderInner(2)
            }
            
            ListView {
                id: tabListView
                anchors.fill: parent
                orientation: root.orientation === "horizontal" ? ListView.Horizontal : ListView.Vertical
                model: root.tabs
                interactive: false
                clip: true
                
                delegate: Rectangle {
                    width: root.orientation === "horizontal" ? tabBar.width / root.tabs.length : tabBar.width
                    height: root.orientation === "vertical" ? tabBar.height / root.tabs.length : tabBar.height
                    
                    color: index === root.currentIndex ? MElevation.getSurface(0) : "transparent"
                    
                    Behavior on color {
                        enabled: Constants.enableAnimations
                        ColorAnimation { duration: Constants.animationFast }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.bottomMargin: root.orientation === "horizontal" ? 0 : Constants.borderWidthThin
                        anchors.rightMargin: root.orientation === "vertical" ? 0 : Constants.borderWidthThin
                        color: "transparent"
                        border.width: index === root.currentIndex ? Constants.borderWidthMedium : 0
                        border.color: MColors.accent
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.currentIndex = index
                            root.tabChanged(index)
                        }
                    }
                    
                    Text {
                        text: modelData
                        anchors.centerIn: parent
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: index === root.currentIndex ? Font.DemiBold : Font.Normal
                        color: index === root.currentIndex ? MColors.accent : MColors.text
                    }
                }
            }
        }
        
        StackLayout {
            id: stackLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentIndex
        }
    }
}

