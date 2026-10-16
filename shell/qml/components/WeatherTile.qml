import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// One of the weather sheet's detail tiles; children go under the value.
Rectangle {
    id: tile

    property string glyph
    property string title
    property string value
    property string detail
    default property alias extra: more.data

    height: column.height + 2 * Silica.Theme.paddingLarge
    radius: Silica.Theme.paddingMedium
    color: Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, 0.1)

    Column {
        id: column

        x: Silica.Theme.paddingLarge
        y: Silica.Theme.paddingLarge
        width: parent.width - 2 * x
        spacing: Silica.Theme.paddingSmall

        Row {
            spacing: Silica.Theme.paddingSmall

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: tile.glyph
                size: Silica.Theme.fontSizeSmall
                color: Silica.Theme.secondaryHighlightColor
            }
            Silica.Label {
                text: tile.title
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                color: Silica.Theme.secondaryHighlightColor
            }
        }
        Silica.Label {
            width: parent.width
            truncationMode: Silica.TruncationMode.Fade
            text: tile.value
            font.pixelSize: Silica.Theme.fontSizeLarge
        }
        Item {
            id: more

            width: parent.width
            height: childrenRect.height
            visible: children.length > 0
        }
        Silica.Label {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.Wrap
            text: tile.detail
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
            color: Silica.Theme.secondaryColor
        }
    }
}
