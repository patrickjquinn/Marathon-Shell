import QtQuick
import MarathonOS.Shell

Rectangle {
    id: listItem
    
    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property string value: ""
    property bool showChevron: false
    property bool showToggle: false
    property bool toggleValue: false
    
    signal settingClicked()
    signal toggleChanged(bool value)
    
    width: parent ? parent.width : 0
    height: subtitle !== "" ? Constants.touchTargetLarge : Constants.touchTargetMedium
    color: "transparent"
    
    // Glass morphism background (OpenStream.FM inspired)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(255, 255, 255, 0.02)
        opacity: mouseArea.pressed ? 1 : 0
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.04)
        radius: 4
        
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }
    
    // Press feedback
    Rectangle {
        anchors.fill: parent
        color: Colors.accent
        opacity: mouseArea.pressed ? 0.05 : 0
        radius: 4
        
        Behavior on opacity {
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }
    }
    
    // Press feedback
    transform: Translate {
        y: mouseArea.pressed && !showToggle ? -2 : 0
        
        Behavior on y {
            NumberAnimation { 
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }
    
    Item {
        anchors.fill: parent
        anchors.margins: 16
        
        Icon {
            id: iconImage
            visible: iconName !== ""
            name: iconName
            size: 24
            color: Colors.text
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Column {
            id: titleColumn
            anchors.left: iconImage.visible ? iconImage.right : parent.left
            anchors.leftMargin: iconImage.visible ? 16 : 0
            anchors.right: rightContent.left
            anchors.rightMargin: Constants.spacingMedium
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            
            Text {
                text: title
                color: Colors.text
                font.pixelSize: Typography.sizeBody
                font.weight: Font.DemiBold
                font.family: Typography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                visible: subtitle !== ""
                text: subtitle
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeSmall
                font.family: Typography.fontFamily
                elide: Text.ElideRight
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                opacity: 0.7
            }
        }
        
        Item {
            id: rightContent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: showToggle ? 60 : showChevron ? (valueText.visible ? valueText.width + 36 : 20) : (valueText.visible ? valueText.width : 0)
            height: parent.height
            
            Text {
                id: valueText
                visible: value !== "" && !showToggle
                text: value
                color: Colors.textTertiary
                font.pixelSize: Typography.sizeSmall
                font.family: Typography.fontFamily
                anchors.right: chevronImage.visible ? chevronImage.left : parent.right
                anchors.rightMargin: chevronImage.visible ? 16 : 0
                anchors.verticalCenter: parent.verticalCenter
            }
            
            MarathonToggle {
                id: toggleItem
                visible: showToggle
                checked: toggleValue
                width: Constants.touchTargetSmall
                height: 32
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                
                onToggled: (value) => {
                    toggleChanged(value)
                }
            }
            
            Image {
                id: chevronImage
                visible: showChevron && !showToggle
                source: "qrc:/images/icons/lucide/chevron-down.svg"
                width: 20
                height: Constants.navBarHeight
                rotation: -90
                fillMode: Image.PreserveAspectFit
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: iconName !== "" ? 56 : 16
        height: 1
        color: Qt.rgba(255, 255, 255, 0.08)
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !showToggle
        
        z: 100
        
        onClicked: {
            Logger.info("SettingsListItem", "Clicked: " + title)
            listItem.settingClicked()
        }
    }
}

