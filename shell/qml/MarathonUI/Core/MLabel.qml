import QtQuick
import MarathonOS.Shell

Text {
    id: root
    
    property string variant: "body"
    
    font.pixelSize: {
        switch (variant) {
            case "h1": return Constants.fontSizeHuge
            case "h2": return Constants.fontSizeXXLarge
            case "h3": return Constants.fontSizeXLarge
            case "h4": return Constants.fontSizeLarge
            case "body": return Constants.fontSizeMedium
            case "caption": return Constants.fontSizeSmall
            case "overline": return Constants.fontSizeXSmall
            default: return Constants.fontSizeMedium
        }
    }
    
    font.weight: {
        switch (variant) {
            case "h1":
            case "h2":
            case "h3":
                return Font.Bold
            case "h4":
                return Font.DemiBold
            default:
                return Font.Normal
        }
    }
    
    color: {
        switch (variant) {
            case "overline":
            case "caption":
                return MColors.textSecondary
            default:
                return MColors.text
        }
    }
    
    wrapMode: Text.WordWrap
    elide: Text.ElideRight
}

