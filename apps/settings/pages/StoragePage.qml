import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings

Page {
    id: page

    StorageInfo {
        id: storage
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Storage")
            }
            ProgressBar {
                objectName: "usageBar"
                width: parent.width
                minimumValue: 0
                maximumValue: 1
                value: storage.usedPercentage
                label: qsTr("%1 used of %2").arg(storage.usedSpaceString).arg(storage.totalSpaceString)
            }
            DetailItem {
                objectName: "usedItem"
                label: qsTr("Used")
                value: storage.usedSpaceString
            }
            DetailItem {
                objectName: "availableItem"
                label: qsTr("Available")
                value: storage.availableSpaceString
            }
            DetailItem {
                objectName: "totalItem"
                label: qsTr("Capacity")
                value: storage.totalSpaceString
            }
        }

        VerticalScrollDecorator {}
    }
}
