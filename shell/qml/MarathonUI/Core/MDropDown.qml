import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property string label: ""
    property var model: []
    property int currentIndex: -1
    property string currentValue: currentIndex >= 0 && currentIndex < model.length ? model[currentIndex] : ""
    property bool expanded: false
    
    signal selected(int index, string value)
    
    implicitWidth: 200
    implicitHeight: Constants.touchTargetMedium
    
    color: MElevation.getSurface(1)
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: expanded ? MColors.accent : MElevation.getBorderOuter(1)
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
        border.color: MElevation.getBorderInner(1)
        antialiasing: Constants.enableAntialiasing
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.expanded = !root.expanded
            if (root.expanded) {
                dropdown.open()
            } else {
                dropdown.close()
            }
        }
    }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingMedium
        anchors.rightMargin: Constants.spacingMedium
        spacing: Constants.spacingSmall
        
        Text {
            text: root.currentValue || root.label
            font.pixelSize: Constants.fontSizeMedium
            color: root.currentValue ? MColors.text : MColors.textSecondary
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: parent.width - chevronIcon.width - parent.spacing
        }
        
        Icon {
            id: chevronIcon
            name: root.expanded ? "chevron-up" : "chevron-down"
            size: Constants.iconSizeMedium
            color: MColors.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    Popup {
        id: dropdown
        y: parent.height + Constants.spacingSmall
        width: parent.width
        height: Math.min(listView.contentHeight + Constants.spacingMedium * 2, Constants.modalMaxHeight * 0.5)
        
        padding: 0
        modal: false
        dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        onClosed: root.expanded = false
        
        background: Rectangle {
            color: MElevation.getSurface(3)
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthThin
            border.color: MElevation.getBorderOuter(3)
            antialiasing: Constants.enableAntialiasing
            
            Rectangle {
                anchors.fill: parent
                anchors.margins: Constants.borderWidthThin
                radius: parent.radius - Constants.borderWidthThin
                color: "transparent"
                border.width: Constants.borderWidthThin
                border.color: MElevation.getBorderInner(3)
                antialiasing: Constants.enableAntialiasing
            }
        }
        
        contentItem: ListView {
            id: listView
            clip: true
            model: root.model
            currentIndex: root.currentIndex
            
            delegate: Rectangle {
                width: ListView.view.width
                height: Constants.touchTargetMedium
                color: mouseArea.pressed ? MElevation.getSurface(0) : (index === root.currentIndex ? MElevation.getSurface(2) : "transparent")
                
                Behavior on color {
                    enabled: Constants.enableAnimations
                    ColorAnimation { duration: Constants.animationFast }
                }
                
                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    onClicked: {
                        root.currentIndex = index
                        root.selected(index, modelData)
                        dropdown.close()
                    }
                }
                
                Text {
                    text: modelData
                    font.pixelSize: Constants.fontSizeMedium
                    color: index === root.currentIndex ? MColors.accent : MColors.text
                    verticalAlignment: Text.AlignVCenter
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.rightMargin: Constants.spacingMedium
                }
            }
        }
    }
}

