import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property string title: ""
    property alias content: contentItem.children
    property bool showing: false
    
    signal closed()
    signal accepted()
    
    anchors.fill: parent
    color: MColors.overlay
    visible: opacity > 0
    opacity: showing ? 1.0 : 0.0
    z: Constants.zIndexQuickSettings + 100
    
    Behavior on opacity {
        enabled: Constants.enableAnimations
        NumberAnimation { duration: Constants.animationNormal }
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: root.closed()
    }
    
    Rectangle {
        id: modalContainer
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, Constants.modalMaxWidth)
        height: Math.min(parent.height * 0.8, Constants.modalMaxHeight)
        
        color: MElevation.getSurface(3)
        radius: Constants.borderRadiusSmall
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderOuter(3)
        antialiasing: Constants.enableAntialiasing
        
        Rectangle {
            id: innerBorder
            anchors.fill: parent
            anchors.margins: Constants.borderWidthThin
            radius: parent.radius > 0 ? parent.radius - Constants.borderWidthThin : 0
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MElevation.getBorderInner(3)
            antialiasing: Constants.enableAntialiasing
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }
        
        Column {
            anchors.fill: parent
            anchors.margins: Constants.spacingLarge
            spacing: Constants.spacingMedium
            
            Text {
                text: root.title
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.DemiBold
                color: MColors.text
                visible: root.title !== ""
                width: parent.width
            }
            
            Item {
                id: contentItem
                width: parent.width
                height: parent.height - (root.title !== "" ? (Constants.fontSizeXLarge + Constants.spacingMedium) : 0)
            }
        }
    }
    
    function show() {
        showing = true
    }
    
    function hide() {
        showing = false
    }
}

