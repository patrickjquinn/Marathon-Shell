import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

/**
 * MListItem - Standard list item with icon, text, and action area
 * 
 * Features:
 * - Proper constraints preventing content overflow
 * - Support for leading icon, title, subtitle
 * - Trailing action area (toggle, button, chevron, custom content)
 * - Built-in press states and interactions
 * - Consistent spacing and sizing
 * 
 * Usage:
 *   MListItem {
 *       leadingIcon: "bluetooth"
 *       title: "Bluetooth"
 *       subtitle: "Enabled"
 *       trailingContent: MarathonToggle { ... }
 *   }
 */
Rectangle {
    id: root
    
    // Content properties
    property string leadingIcon: ""
    property int leadingIconSize: 32
    property color leadingIconColor: MColors.text
    
    property string title: ""
    property string subtitle: ""
    
    property alias trailingContent: trailingLoader.sourceComponent
    property bool showChevron: false
    property bool enabled: true
    
    // Interaction
    property bool clickable: false
    signal clicked()
    
    // Styling
    property color backgroundColor: Qt.rgba(255, 255, 255, 0.04)
    property color backgroundHoverColor: Qt.rgba(255, 255, 255, 0.06)
    property color borderColor: Qt.rgba(255, 255, 255, 0.08)
    
    // Size
    width: parent.width
    height: Constants.appIconSize
    radius: Constants.borderRadiusSharp
    
    // Appearance
    color: clickable && mouseArea.pressed ? backgroundHoverColor : backgroundColor
    border.width: 1
    border.color: borderColor
    
    Behavior on color {
        ColorAnimation { duration: 150 }
    }
    
    // Layout: [Icon] [Text Content] [Trailing]
    // Using anchors for proper constraints
    
    // Leading icon
    Icon {
        id: leadingIconItem
        anchors.left: parent.left
        anchors.leftMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        name: leadingIcon
        size: leadingIconSize
        color: leadingIconColor
        visible: leadingIcon !== ""
    }
    
    // Text content (constrained between icon and trailing)
    Column {
        id: textContent
        anchors.left: leadingIcon !== "" ? leadingIconItem.right : parent.left
        anchors.leftMargin: leadingIcon !== "" ? Constants.spacingMedium : Constants.spacingMedium
        anchors.right: trailingArea.left
        anchors.rightMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingXSmall
        
        Text {
            id: titleText
            text: root.title
            width: parent.width
            color: MColors.text
            font.pixelSize: Constants.fontSizeMedium
            font.weight: Font.DemiBold
            font.family: MTypography.fontFamily
            elide: Text.ElideRight
            opacity: root.enabled ? 1.0 : 0.5
        }
        
        Text {
            id: subtitleText
            text: root.subtitle
            width: parent.width
            color: MColors.textSecondary
            font.pixelSize: Constants.fontSizeSmall
            font.family: MTypography.fontFamily
            elide: Text.ElideRight
            visible: subtitle !== ""
            opacity: root.enabled ? 1.0 : 0.5
        }
    }
    
    // Trailing area (right-anchored, fixed position)
    Item {
        id: trailingArea
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(childrenRect.width, showChevron ? 24 : 0)
        height: parent.height - (Constants.spacingMedium * 2)
        
        Loader {
            id: trailingLoader
            anchors.centerIn: parent
        }
        
        Icon {
            name: "chevron-right"
            size: Constants.iconSizeSmall
            color: MColors.textTertiary
            anchors.centerIn: parent
            visible: showChevron && !trailingLoader.item
        }
    }
    
    // Click interaction
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.clickable
        onClicked: root.clicked()
    }
}

