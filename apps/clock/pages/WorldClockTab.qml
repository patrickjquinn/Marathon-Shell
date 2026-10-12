import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TabItem {
    id: root

    property var app
    property real topMargin
    property date now: new Date()

    flickable: list

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.isCurrentItem && Qt.application.state === Qt.ApplicationActive
        onTriggered: root.now = new Date()
    }

    SilicaListView {
        id: list

        objectName: "cityList"
        anchors.fill: parent
        model: root.app.cities

        PullDownMenu {
            MenuItem {
                text: qsTr("Add city")
                onClicked: pageStack.push(Qt.resolvedUrl("AddCityPage.qml"), { app: root.app })
            }
        }

        header: Column {
            width: list.width
            topPadding: root.topMargin + Theme.paddingLarge * 2
            bottomPadding: Theme.paddingLarge

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Format.formatDate(root.now, Formatter.TimeValue)
                font.pixelSize: Theme.fontSizeHuge
                font.features: ({ "tnum": 1 })
                color: Theme.highlightColor
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Format.formatDate(root.now, Formatter.DateLong)
                color: Theme.secondaryHighlightColor
            }
        }

        ViewPlaceholder {
            enabled: list.count === 0
            text: qsTr("No cities")
            hintText: qsTr("Pull down to add one")
        }

        delegate: ListItem {
            id: item

            required property int index
            required property var modelData
            readonly property var info: root.app.cityTime(modelData, root.now)

            objectName: "cityItem"
            contentHeight: Theme.itemSizeMedium
            Accessible.name: modelData.name + ", " + info.time
            menu: ContextMenu {
                MenuItem {
                    visible: item.index > 0
                    text: qsTr("Move up")
                    onClicked: root.app.moveCity(item.index, item.index - 1)
                }
                MenuItem {
                    visible: item.index < list.count - 1
                    text: qsTr("Move down")
                    onClicked: root.app.moveCity(item.index, item.index + 1)
                }
                MenuItem {
                    text: qsTr("Remove")
                    onClicked: {
                        const app = root.app;
                        const name = item.modelData.name;
                        item.remorseDelete(() => app.removeCity(name));
                    }
                }
            }

            Column {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: times.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.modelData.name
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    text: item.info.diff
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
            Column {
                id: times

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    anchors.right: parent.right
                    text: item.info.time
                    font.pixelSize: Theme.fontSizeLarge
                    font.features: ({ "tnum": 1 })
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    anchors.right: parent.right
                    text: item.info.weekday
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
