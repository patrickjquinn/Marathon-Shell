import QtQuick
import MarathonOS.Shell

Item {
    id: root
    
    property string title: ""
    property string subtitle: ""
    property string leftIconName: ""
    property string rightIconName: "chevron-right"
    property bool showRightIcon: true
    property bool showDivider: true
    property var contextualActions: []
    property real swipeThreshold: 0.3
    
    signal clicked()
    signal contextualActionTriggered(int index, string action)
    
    implicitWidth: parent ? parent.width : 300
    implicitHeight: subtitle ? 72 : 56
    clip: true
    
    Row {
        id: actionsRow
        anchors.right: mainContent.left
        height: parent.height
        spacing: 0
        visible: root.contextualActions.length > 0
        
        Repeater {
            model: root.contextualActions
            
            Rectangle {
                width: Constants.touchTargetLarge
                height: actionsRow.height
                color: modelData.color || MColors.error
                
                Icon {
                    name: modelData.icon || "trash"
                    size: Constants.iconSizeMedium
                    color: MColors.text
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.contextualActionTriggered(index, modelData.action || "")
                        mainContent.x = 0
                    }
                }
            }
        }
    }
    
    Rectangle {
        id: mainContent
        width: root.width
        height: root.height
        x: 0
        color: mouseArea.pressed ? MColors.glass : MElevation.getSurface(1)
        
        Behavior on color {
            enabled: Constants.enableAnimations
            ColorAnimation { duration: Constants.animationFast }
        }
        
        Behavior on x {
            enabled: Constants.enableAnimations && !dragArea.drag.active
            SmoothedAnimation { velocity: 1000 }
        }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingLarge
        anchors.rightMargin: Constants.spacingLarge
        spacing: Constants.spacingMedium
        
        Icon {
            visible: leftIconName !== ""
            name: leftIconName
            size: Constants.iconSizeMedium
            color: MColors.text
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Column {
            width: parent.width - (leftIconName !== "" ? Constants.iconSizeMedium + parent.spacing : 0) - (showRightIcon ? Constants.iconSizeSmall + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Constants.spacingXSmall
            
            Text {
                text: root.title
                color: MColors.text
                font.pixelSize: Constants.fontSizeMedium
                font.weight: Font.Medium
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                visible: subtitle !== ""
                text: subtitle
                color: MColors.textSecondary
                font.pixelSize: Constants.fontSizeSmall
                elide: Text.ElideRight
                width: parent.width
            }
        }
        
        Icon {
            visible: showRightIcon
            name: rightIconName
            size: Constants.iconSizeSmall
            color: MColors.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    }
    
    Rectangle {
        visible: showDivider
        anchors.bottom: mainContent.bottom
        anchors.left: mainContent.left
        anchors.right: mainContent.right
        anchors.leftMargin: Constants.spacingLarge
        height: Constants.borderWidthThin
        color: MColors.border
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: mainContent
        enabled: !dragArea.drag.active
        onClicked: {
            if (Math.abs(mainContent.x) < 5) {
                root.clicked()
            }
        }
    }
    
    MouseArea {
        id: dragArea
        anchors.fill: mainContent
        enabled: root.contextualActions.length > 0
        
        property real startX: 0
        property real startTime: 0
        
        drag.target: mainContent
        drag.axis: Drag.XAxis
        drag.minimumX: -actionsRow.width
        drag.maximumX: 0
        
        onPressed: function(mouse) {
            startX = mainContent.x
            startTime = Date.now()
        }
        
        onReleased: function(mouse) {
            var delta = mainContent.x - startX
            var time = Date.now() - startTime
            var velocity = Math.abs(delta) / time
            
            if (Math.abs(mainContent.x) > actionsRow.width * root.swipeThreshold || velocity > 0.5) {
                mainContent.x = -actionsRow.width
            } else {
                mainContent.x = 0
            }
        }
    }
    
    function resetSwipe() {
        mainContent.x = 0
    }
}

