import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonOS.Shell

Item {
    id: root

    property string iconName: "inbox"
    property string title: "Nothing here yet"
    property string message: ""
    property string actionText: ""
    // DESIGN pixels. Core/Icon.qml's `size` is a plain int with no scaling of
    // its own, so this component scales it at the point of use below. Doing it
    // here rather than in the default means the call sites that pass their own
    // value (several pass 64) scale too — previously they pinned the glyph to a
    // fixed physical size that shrank against the copy as user scale rose.
    property int iconSize: 80

    signal actionClicked

    Column {
        anchors.centerIn: parent
        // The 400 cap is a DESIGN-pixel measure and has to scale. Unscaled,
        // every empty state was pinned to 400 physical px whatever the user
        // scale — 56% of a 720 px screen — so body copy wrapped early and
        // orphaned its last word ("...to write your first / note.").
        width: Math.min(parent.width * 0.8, Math.round(400 * (Constants.scaleFactor || 1.0)))
        spacing: MSpacing.lg

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: iconName
            size: Math.round(root.iconSize * (Constants.scaleFactor || 1.0))
            color: MColors.textTertiary
            opacity: 0.6
        }

        Column {
            width: parent.width
            spacing: MSpacing.sm

            MLabel {
                width: parent.width
                text: title
                variant: "primary"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }

            MLabel {
                width: parent.width
                text: message
                variant: "secondary"
                font.pixelSize: MTypography.sizeBody
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: message.length > 0
            }
        }

        MButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: actionText
            variant: "primary"
            // Empty-state CTA is a primary action — use the large size so it
            // reads as a proper padded button, not tight-wrapped text.
            size: "large"
            visible: actionText.length > 0
            onClicked: root.actionClicked()
        }
    }
}
