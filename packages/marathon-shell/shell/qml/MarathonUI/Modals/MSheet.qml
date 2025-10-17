import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Item {
    id: root
    
    property string title: ""
    property alias content: contentItem.children
    property bool showing: false
    property real dragThreshold: 0.3
    
    signal closed()
    signal accepted()
    
    anchors.fill: parent
    visible: opacity > 0
    opacity: showing ? 1.0 : 0.0
    z: Constants.zIndexQuickSettings + 200
    
    Behavior on opacity {
        enabled: Constants.enableAnimations
        NumberAnimation { duration: Constants.animationNormal }
    }
    
    MouseArea {
        anchors.fill: parent
        enabled: root.showing
        onClicked: root.close()
    }
    
    Rectangle {
        id: sheetContainer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(parent.height * 0.7, contentColumn.implicitHeight + Constants.spacingXLarge * 2)
        
        color: MElevation.getSurface(4)
        radius: 0
        
        transform: Translate {
            id: sheetTranslate
            y: root.showing ? 0 : sheetContainer.height
            
            Behavior on y {
                enabled: Constants.enableAnimations
                SmoothedAnimation { 
                    velocity: 2000
                    duration: Constants.animationNormal
                }
            }
        }
        
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 0
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MElevation.getBorderOuter(4)
            radius: Constants.borderRadiusSmall
        }
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: Constants.borderWidthThin
            anchors.topMargin: Constants.borderWidthThin
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MElevation.getBorderInner(4)
            radius: Constants.borderRadiusSmall - Constants.borderWidthThin
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {}
            
            property real startY: 0
            property real startTime: 0
            
            onPressed: function(mouse) {
                startY = mouse.y
                startTime = Date.now()
            }
            
            onPositionChanged: function(mouse) {
                if (pressed && mouse.y > startY) {
                    var delta = mouse.y - startY
                    sheetTranslate.y = Math.max(0, delta)
                }
            }
            
            onReleased: function(mouse) {
                var delta = mouse.y - startY
                var time = Date.now() - startTime
                var velocity = delta / time
                
                if (delta > sheetContainer.height * root.dragThreshold || velocity > 0.5) {
                    root.close()
                } else {
                    sheetTranslate.y = 0
                }
            }
        }
        
        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Constants.spacingLarge
            spacing: Constants.spacingMedium
            
            Rectangle {
                width: Constants.touchTargetLarge
                height: 4
                radius: Constants.borderRadiusSharp
                color: MColors.borderInner
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
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
                height: parent.height - (root.title !== "" ? (Constants.fontSizeXLarge + Constants.spacingMedium) : 0) - Constants.spacingMedium - 4
            }
        }
    }
    
    function show() {
        showing = true
    }
    
    function close() {
        showing = false
        Qt.callLater(() => root.closed())
    }
}

