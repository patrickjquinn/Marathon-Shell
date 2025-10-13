import QtQuick
import "../Theme"

Rectangle {
    id: root
    
    property string text: ""
    property string variant: "error"
    
    implicitWidth: Math.max(20, badgeText.width + MSpacing.sm * 2)
    implicitHeight: 20
    radius: MRadius.pill
    
    color: {
        if (variant === "success") return MColors.success
        if (variant === "warning") return MColors.warning
        if (variant === "info") return MColors.info
        return MColors.error
    }
    
    Text {
        id: badgeText
        text: root.text
        color: MColors.text
        font.pixelSize: MTypography.sizeTiny
        font.weight: MTypography.weightBold
        font.family: MTypography.fontFamily
        anchors.centerIn: parent
    }
}

