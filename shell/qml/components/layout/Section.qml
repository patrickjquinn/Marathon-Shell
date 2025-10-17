import QtQuick
import MarathonOS.Shell

Item {
    id: section
    
    property string title: ""
    property string subtitle: ""
    default property alias content: contentColumn.children
    
    width: parent.width
    height: headerColumn.height + contentCard.height + (title !== "" ? 16 : 0)
    
    Column {
        id: headerColumn
        width: parent.width
        spacing: 6
        visible: title !== ""
        
        Text {
            text: title
            color: Colors.text
            font.pixelSize: Typography.sizeLarge
            font.weight: Font.DemiBold
            font.family: Typography.fontFamily
        }
        
        Text {
            visible: subtitle !== ""
            text: subtitle
            color: Colors.textSecondary
            font.pixelSize: Typography.sizeSmall
            font.family: Typography.fontFamily
            wrapMode: Text.WordWrap
            width: parent.width
            opacity: 0.7
        }
    }
    
    Rectangle {
        id: contentCard
        anchors.top: headerColumn.bottom
        anchors.topMargin: title !== "" ? 16 : 0
        width: parent.width
        height: contentColumn.height
        color: Qt.rgba(255, 255, 255, 0.04)
        radius: 4
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.12)
        layer.enabled: false  // Disable layer for better ShaderEffectSource capture
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.03)
        }
        
        Column {
            id: contentColumn
            width: parent.width
        }
    }
}

