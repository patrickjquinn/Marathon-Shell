import QtQuick
import "../Theme"

Rectangle {
    id: root
    
    property string title: ""
    property string subtitle: ""
    property string leftIconName: ""
    property string rightIconName: "chevron-right"
    property bool showRightIcon: true
    property bool showDivider: true
    
    signal clicked()
    
    implicitWidth: parent.width
    implicitHeight: subtitle ? 72 : 56
    color: mouseArea.pressed ? MColors.glass : "transparent"
    
    Behavior on color { ColorAnimation { duration: 150 } }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.lg
        anchors.rightMargin: MSpacing.lg
        spacing: MSpacing.md
        
        Image {
            visible: leftIconName !== ""
            source: leftIconName !== "" ? "qrc:/images/icons/lucide/" + leftIconName + ".svg" : ""
            width: 24
            height: 24
            fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
            smooth: true
            antialiasing: true
        }
        
        Column {
            width: parent.width - (leftIconName !== "" ? 48 : 0) - (showRightIcon ? 40 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: MSpacing.xs
            
            Text {
                text: root.title
                color: MColors.text
                font.pixelSize: MTypography.sizeBody
                font.weight: MTypography.weightMedium
                font.family: MTypography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                visible: subtitle !== ""
                text: subtitle
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
        }
        
        Image {
            visible: showRightIcon
            source: "qrc:/images/icons/lucide/" + rightIconName + ".svg"
            width: 20
            height: 20
            fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
            smooth: true
            antialiasing: true
        }
    }
    
    Rectangle {
        visible: showDivider
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: MSpacing.lg
        height: 1
        color: MColors.border
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }
}

