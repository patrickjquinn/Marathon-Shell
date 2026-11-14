pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property string title
    // [{ title, text }]
    property var sections: []

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: page.title
            }
            Repeater {
                model: page.sections

                Column {
                    id: section

                    required property var modelData

                    width: column.width

                    SectionHeader {
                        text: section.modelData.title
                    }
                    Label {
                        id: legalText

                        x: Theme.horizontalPageMargin
                        // About 70 characters a line at most, with room between them.
                        width: Math.min(parent.width - 2 * Theme.horizontalPageMargin, legalText.font.pixelSize * 34)
                        wrapMode: Text.Wrap
                        lineHeight: 1.1
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.highlightColor
                        text: section.modelData.text
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
