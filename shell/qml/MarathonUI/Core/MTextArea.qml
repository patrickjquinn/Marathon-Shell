import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property alias text: textArea.text
    property alias placeholderText: textArea.placeholderText
    property alias readOnly: textArea.readOnly
    property int maxLength: 5000
    property bool showCharCount: false
    
    implicitWidth: 300
    implicitHeight: 120
    
    color: MElevation.getSurface(0)
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: textArea.activeFocus ? MColors.accent : MElevation.getBorderOuter(0)
    antialiasing: Constants.enableAntialiasing
    
    Behavior on border.color {
        enabled: Constants.enableAnimations
        ColorAnimation { duration: Constants.animationFast }
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin
        radius: parent.radius - Constants.borderWidthThin
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: Qt.rgba(0, 0, 0, 1.0)
        antialiasing: Constants.enableAntialiasing
    }
    
    Flickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        anchors.bottomMargin: root.showCharCount ? Constants.fontSizeSmall + Constants.spacingMedium * 2 : Constants.spacingMedium
        
        contentWidth: textArea.paintedWidth
        contentHeight: textArea.paintedHeight
        clip: true
        
        TextArea.flickable: TextArea {
            id: textArea
            width: flickable.width
            wrapMode: TextArea.Wrap
            selectByMouse: true
            
            font.pixelSize: Constants.fontSizeMedium
            color: MColors.text
            selectionColor: MColors.accent
            selectedTextColor: MColors.text
            placeholderTextColor: MColors.textTertiary
            
            background: Rectangle {
                color: "transparent"
            }
            
            onTextChanged: {
                if (text.length > root.maxLength) {
                    text = text.substring(0, root.maxLength)
                }
            }
        }
        
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            visible: flickable.contentHeight > flickable.height
        }
    }
    
    Text {
        visible: root.showCharCount
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Constants.spacingSmall
        text: textArea.text.length + " / " + root.maxLength
        font.pixelSize: Constants.fontSizeSmall
        color: textArea.text.length >= root.maxLength ? MColors.warning : MColors.textTertiary
    }
}

