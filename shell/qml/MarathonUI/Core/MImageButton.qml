import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property alias source: image.source
    property string text: ""
    property bool disabled: false
    property int imageSize: Constants.iconSizeXLarge
    
    signal clicked()
    signal pressed()
    signal released()
    
    implicitWidth: Math.max(imageSize + Constants.spacingLarge * 2, 100)
    implicitHeight: text !== "" ? imageSize + Constants.fontSizeMedium + Constants.spacingLarge * 2 : imageSize + Constants.spacingLarge * 2
    
    color: disabled ? MElevation.getSurface(0) : (mouseArea.pressed ? MElevation.getSurface(1) : MElevation.getSurface(2))
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(2)
    antialiasing: Constants.enableAntialiasing
    
    Behavior on color {
        enabled: Constants.enableAnimations
        ColorAnimation { duration: Constants.animationFast }
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin
        radius: parent.radius - Constants.borderWidthThin
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderInner(2)
        antialiasing: Constants.enableAntialiasing
    }
    
    Column {
        anchors.centerIn: parent
        spacing: Constants.spacingSmall
        
        Image {
            id: image
            width: root.imageSize
            height: root.imageSize
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(root.imageSize, root.imageSize)
            smooth: true
            antialiasing: Constants.enableAntialiasing
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.disabled ? 0.5 : 1.0
        }
        
        Text {
            visible: root.text !== ""
            text: root.text
            font.pixelSize: Constants.fontSizeMedium
            color: root.disabled ? MColors.textDisabled : MColors.text
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !root.disabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        
        onPressed: root.pressed()
        onReleased: root.released()
        onClicked: root.clicked()
    }
}

