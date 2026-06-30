import QtQuick
import MarathonUI.Theme

// MLabel — role-driven Text. Pull size/weight/tracking from the
// MTypography role table (see MTypography.qml). Replaces the legacy
// 5-variant exposure (display/xlarge/large/small/xsmall) with the
// full role set so callers can write `variant: "title2"` instead of
// hand-rolling Text { font.pixelSize: MTypography.sizeTitle2 ... }.
//
// Legacy size-aliases (xlarge/large/small/xsmall) still map to their
// closest M3E role for back-compat. New code: use the role names.
//
// emphasized: pulls the additive M3 Expressive emphasized weight tier
// (per MTypography.weightFor) — selection states, alerts, headlines
// that need authority.
//
// colorRole keeps the original semantic — primary/secondary/tertiary/
// hint/accent — independently of the typography role.
Text {
    id: root

    // Typography role — display/titleL/title1/title2/title3/headline/
    // body/callout/subhead/footnote/caption/eyebrow/mono. Legacy
    // aliases below.
    property string variant: "body"
    property bool emphasized: false

    // Color role — primary/secondary/tertiary/hint/accent. Independent
    // of typography role.
    property string colorRole: "primary"

    // Resolve a possibly-legacy variant to a current role name.
    readonly property string _role: {
        switch (root.variant) {
        case "display":
        case "titleL":
        case "title1":
        case "title2":
        case "title3":
        case "headline":
        case "body":
        case "callout":
        case "subhead":
        case "footnote":
        case "caption":
        case "eyebrow":
        case "mono":
            return root.variant;
        // Legacy aliases — keep mapping forever for back-compat.
        case "xlarge":
            return "title2";
        case "large":
            return "headline";
        case "small":
            return "footnote";
        case "xsmall":
            return "caption";
        }
        return "body";
    }

    color: {
        switch (root.colorRole) {
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
        }
        // Legacy fallback for callers that used colorRole=variant.
        switch (root.variant) {
        case "secondary":
            return MColors.textSecondary;
        case "tertiary":
            return MColors.textTertiary;
        case "hint":
            return MColors.textHint;
        case "accent":
            return MColors.marathonTeal;
        }
        return MColors.textPrimary;
    }

    font.pixelSize: MTypography.sizeFor(_role)
    font.weight: MTypography.weightFor(_role, root.emphasized)
    font.letterSpacing: MTypography.trackingFor(_role)
    font.family: MTypography.fontFamily
    font.capitalization: _role === "eyebrow" ? Font.AllUppercase : Font.MixedCase

    Accessible.role: _role === "display" || _role === "titleL" || _role === "title1" || _role === "title2" || _role === "title3" || _role === "headline" ? Accessible.Heading : Accessible.StaticText
    Accessible.name: text
    Accessible.readOnly: true
}
