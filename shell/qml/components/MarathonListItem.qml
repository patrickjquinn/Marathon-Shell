import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: listItem
    width: parent.width
    height: Constants.hubHeaderHeight
    color: pressed ? Colors.surfaceLight : Colors.surface
    
    property string title: ""
    property string subtitle: ""
    property string time: ""
    property string iconSource: ""
    property color iconColor: Colors.accent
    property bool showDelete: false
    property bool pressed: false
    
    signal clicked()
    signal deleteClicked()
    
    Behavior on color {
        ColorAnimation { duration: 100 }
    }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingMedium
        anchors.rightMargin: Constants.spacingMedium
        spacing: Constants.spacingMedium
        
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(48 * Constants.scaleFactor)
            height: Math.round(48 * Constants.scaleFactor)
            radius: Colors.cornerRadiusCircle
            color: iconColor
            opacity: 0.2
            
            Image {
                anchors.centerIn: parent
                source: iconSource
                width: Math.round(28 * Constants.scaleFactor)
                height: Math.round(28 * Constants.scaleFactor)
                fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
                smooth: true
            }
        }
        
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Math.round((48 + 100 + 32) * Constants.scaleFactor)
            spacing: Constants.spacingXSmall
            
            Text {
                text: title
                color: Colors.text
                font.pixelSize: MTypography.sizeBody
                font.weight: Font.DemiBold
                font.family: MTypography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                text: subtitle
                color: Colors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
        }
        
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: time
            color: Colors.textTertiary
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
        }
        
        Rectangle {
            visible: showDelete
            anchors.verticalCenter: parent.verticalCenter
            width: Constants.touchTargetMinimum
            height: Constants.touchTargetMinimum
            color: "transparent"
            
            Icon {
                name: "x"
                color: Colors.textSecondary
                size: Constants.iconSizeMedium
                anchors.centerIn: parent
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: deleteClicked()
            }
        }
    }
    
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Constants.dividerHeight
        color: Colors.border
    }
    
    MouseArea {
        anchors.fill: parent
        onPressed: listItem.pressed = true
        onReleased: listItem.pressed = false
        onCanceled: listItem.pressed = false
        onClicked: listItem.clicked()
    }
}

