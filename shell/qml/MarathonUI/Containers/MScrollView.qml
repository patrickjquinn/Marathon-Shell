import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property alias content: flickable.contentItem
    property alias contentHeight: flickable.contentHeight
    property alias contentWidth: flickable.contentWidth
    property bool showScrollIndicators: true
    
    color: "transparent"
    
    Flickable {
        id: flickable
        anchors.fill: parent
        clip: true
        contentHeight: contentItem.childrenRect.height
        contentWidth: width
        
        boundsBehavior: Flickable.StopAtBounds
        
        ScrollBar.vertical: ScrollBar {
            id: verticalScrollBar
            policy: root.showScrollIndicators && flickable.contentHeight > flickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            
            contentItem: Rectangle {
                implicitWidth: 6
                radius: width / 2
                color: verticalScrollBar.pressed ? MColors.accent : MColors.borderHighlight
                opacity: verticalScrollBar.active ? 1.0 : 0.5
                
                Behavior on opacity {
                    enabled: Constants.enableAnimations
                    NumberAnimation { duration: Constants.animationFast }
                }
            }
            
            background: Rectangle {
                implicitWidth: 8
                radius: width / 2
                color: "transparent"
            }
        }
        
        ScrollBar.horizontal: ScrollBar {
            id: horizontalScrollBar
            policy: root.showScrollIndicators && flickable.contentWidth > flickable.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            
            contentItem: Rectangle {
                implicitHeight: 6
                radius: height / 2
                color: horizontalScrollBar.pressed ? MColors.accent : MColors.borderHighlight
                opacity: horizontalScrollBar.active ? 1.0 : 0.5
                
                Behavior on opacity {
                    enabled: Constants.enableAnimations
                    NumberAnimation { duration: Constants.animationFast }
                }
            }
            
            background: Rectangle {
                implicitHeight: 8
                radius: height / 2
                color: "transparent"
            }
        }
    }
}

