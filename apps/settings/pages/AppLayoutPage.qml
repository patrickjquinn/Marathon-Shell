pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    readonly property var columns: [
        { value: 0, title: qsTr("Automatic"), description: qsTr("Fits the screen size") },
        { value: 3, title: qsTr("3"), description: qsTr("Larger icons") },
        { value: 4, title: qsTr("4"), description: qsTr("Balanced layout") },
        { value: 5, title: qsTr("5"), description: qsTr("Compact") }
    ]

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("App grid")
            }
            ComboBox {
                objectName: "columnsCombo"
                width: parent.width
                label: qsTr("Columns")
                description: currentIndex >= 0 ? page.columns[currentIndex].description : ""
                Binding on currentIndex {
                    value: page.columns.findIndex(c => c.value === Settings.appGridColumns)
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.columns

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: Settings.appGridColumns = modelData.value
                        }
                    }
                }
            }
            TextSwitch {
                objectName: "filterSwitch"
                text: qsTr("Hide desktop apps")
                description: qsTr("Leaves out apps not made for phones, here and in the App Store")
                automaticCheck: false
                checked: Settings.filterMobileFriendlyApps
                onClicked: Settings.filterMobileFriendlyApps = !checked
            }
            TextSwitch {
                objectName: "nativeSwitch"
                text: qsTr("Search native apps")
                description: qsTr("Includes installed Linux apps in search")
                automaticCheck: false
                checked: Settings.searchNativeApps
                onClicked: Settings.searchNativeApps = !checked
            }
            TextSwitch {
                objectName: "badgesSwitch"
                text: qsTr("Notification badges")
                description: qsTr("Shows unread counts on app icons")
                automaticCheck: false
                checked: Settings.showNotificationBadges
                onClicked: Settings.showNotificationBadges = !checked
            }
        }

        VerticalScrollDecorator {}
    }
}
