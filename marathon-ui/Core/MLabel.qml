import QtQuick
import MarathonUI.Theme

Text {
    id: root

    property string variant: "body"

    color: {
        switch (variant) {
        case "primary":
            return MColors.textPrimary;
        case "secondary":
            return MColors.textSecondary;
        case "tertiary":
            return MColors.textTertiary;
        case "hint":
            return MColors.textHint;
        case "accent":
            return MColors.marathonTeal;
        default:
            return MColors.textPrimary;
        }
    }

    font.pixelSize: {
        switch (variant) {
        case "display":
            return MTypography.sizeDisplay;
        case "xlarge":
            return MTypography.sizeXXLarge;
        case "large":
            return MTypography.sizeLarge;
        case "small":
            return MTypography.sizeSmall;
        case "xsmall":
            return MTypography.sizeXSmall;
        default:
            return MTypography.sizeBody;
        }
    }

    font.family: MTypography.fontFamily
    font.weight: MTypography.weightNormal
}
