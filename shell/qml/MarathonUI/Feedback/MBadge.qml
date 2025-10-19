import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: root
    
    property string text: ""
    property string variant: "error"
    
    implicitWidth: Math.max(20, badgeText.width + Constants.spacingSmall * 2)
    implicitHeight: 20
    radius: MRadius.pill
    
    color: {
        if (root.variant === "success") return MColors.success
        if (root.variant === "warning") return MColors.warning
        if (root.variant === "info") return MColors.info
        return MColors.error
    }
    
    Text {
        id: badgeText
        text: root.text
        color: MColors.text
        font.pixelSize: Constants.fontSizeXSmall
        font.weight: Font.Bold
        font.family: MTypography.fontFamily
        anchors.centerIn: parent
    }
}

