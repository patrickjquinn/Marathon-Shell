pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app

    SilicaListView {
        id: view

        objectName: "stationsView"
        anchors.fill: parent
        model: page.app.stations

        PullDownMenu {
            enabled: page.app.available
            busy: page.app.busy

            MenuItem {
                objectName: "scanStations"
                text: qsTr("Find stations")
                onClicked: page.app.scan()
            }
        }

        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("Radio")
            }

            Label {
                objectName: "frequency"
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.app.megahertz(page.app.frequency)
                font.pixelSize: Theme.fontSizeHuge * 1.6
                color: page.app.playing ? Theme.highlightColor : Theme.primaryColor
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.app.playing && page.app.radioState.stereo ? qsTr("MHz · stereo") : qsTr("MHz")
                color: Theme.secondaryColor
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge * 2
                enabled: page.app.available && !page.app.busy

                IconButton {
                    objectName: "seekDown"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-previous"
                    Accessible.name: qsTr("Previous station")
                    onClicked: page.app.seek(false)
                }

                IconButton {
                    objectName: "playStop"
                    icon.source: page.app.playing ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
                    Accessible.name: page.app.playing ? qsTr("Stop") : qsTr("Play")
                    onClicked: page.app.playing ? page.app.stop() : page.app.play(page.app.frequency)
                }

                IconButton {
                    objectName: "seekUp"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-next"
                    Accessible.name: qsTr("Next station")
                    onClicked: page.app.seek(true)
                }
            }

            Label {
                objectName: "hint"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                bottomPadding: Theme.paddingLarge
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.app.available ? qsTr("Plug in wired headphones: they are the radio's aerial.") : qsTr("This phone has no FM radio.")
            }

            SectionHeader {
                visible: view.count > 0
                text: qsTr("Stations")
            }
        }

        delegate: ListItem {
            id: item

            required property int modelData

            Accessible.name: qsTr("%1 MHz").arg(page.app.megahertz(modelData))
            onClicked: page.app.play(modelData)

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("%1 MHz").arg(page.app.megahertz(item.modelData))
                color: item.highlighted || (page.app.playing && page.app.frequency === item.modelData) ? Theme.highlightColor : Theme.primaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
