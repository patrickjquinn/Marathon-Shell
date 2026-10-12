pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Open source licenses")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Marathon OS is built from open source components. These are the licenses of the ones in this build.")
            }
            Repeater {
                objectName: "sections"
                model: SettingsController.openSourceLicenses

                Column {
                    id: section

                    required property var modelData

                    width: column.width

                    SectionHeader {
                        text: section.modelData.title
                    }
                    Repeater {
                        model: section.modelData.items

                        Item {
                            id: entry

                            required property var modelData

                            width: section.width
                            height: Theme.itemSizeMedium

                            Column {
                                anchors {
                                    left: parent.left
                                    leftMargin: Theme.horizontalPageMargin
                                    right: license.left
                                    rightMargin: Theme.paddingMedium
                                    verticalCenter: parent.verticalCenter
                                }

                                Label {
                                    width: parent.width
                                    text: entry.modelData.title
                                    truncationMode: TruncationMode.Fade
                                }
                                Label {
                                    width: parent.width
                                    text: entry.modelData.subtitle
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    truncationMode: TruncationMode.Fade
                                    color: Theme.secondaryColor
                                }
                            }
                            Label {
                                id: license

                                anchors {
                                    right: parent.right
                                    rightMargin: Theme.horizontalPageMargin
                                    verticalCenter: parent.verticalCenter
                                }
                                text: entry.modelData.value
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.highlightColor
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
