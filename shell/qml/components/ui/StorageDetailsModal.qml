pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Modal {
    id: storageModal

    title: "Storage"

    Column {
        width: parent.width
        spacing: Silica.Theme.paddingLarge

        Column {
            width: parent.width
            spacing: Silica.Theme.paddingSmall

            Row {
                width: parent.width

                Silica.Label {
                    id: usedLabel

                    text: "Used"
                    color: Silica.Theme.primaryColor
                    width: parent.width / 2
                }

                Silica.Label {
                    text: "45.2 GB of 64 GB"
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignRight
                    width: parent.width / 2
                    height: usedLabel.height
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                width: parent.width
                height: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
                color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)

                Rectangle {
                    width: parent.width * 0.71
                    height: parent.height
                    color: Silica.Theme.highlightColor
                }
            }
        }

        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: [
                    {
                        "name": "Apps",
                        "size": "12.4 GB",
                        "color": "#3498db"
                    },
                    {
                        "name": "Photos",
                        "size": "18.7 GB",
                        "color": "#e74c3c"
                    },
                    {
                        "name": "Videos",
                        "size": "8.3 GB",
                        "color": "#9b59b6"
                    },
                    {
                        "name": "Music",
                        "size": "3.2 GB",
                        "color": "#f39c12"
                    },
                    {
                        "name": "Documents",
                        "size": "2.1 GB",
                        "color": "#2ecc71"
                    },
                    {
                        "name": "Other",
                        "size": "0.5 GB",
                        "color": "#95a5a6"
                    }
                ]

                Silica.DetailItem {
                    id: storageRow

                    required property var modelData

                    width: parent.width
                    leftMargin: 0
                    rightMargin: 0
                    label: storageRow.modelData.name
                    value: storageRow.modelData.size
                }
            }
        }
    }
}
