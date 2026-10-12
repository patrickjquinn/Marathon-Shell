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
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
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
