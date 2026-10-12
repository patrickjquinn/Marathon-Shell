import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: root

    property alias history: historySwitch.checked
    property alias cookies: cookiesSwitch.checked

    objectName: "clearDataDialog"
    canAccept: history || cookies

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                title: qsTr("Clear browsing data")
                acceptText: qsTr("Clear")
            }
            TextSwitch {
                id: historySwitch

                objectName: "historySwitch"
                text: qsTr("History")
                description: qsTr("Pages you've visited")
                checked: true
            }
            TextSwitch {
                id: cookiesSwitch

                objectName: "cookiesSwitch"
                text: qsTr("Cookies and site data")
                description: qsTr("Signs you out of most websites")
                checked: true
            }
        }

        VerticalScrollDecorator {}
    }
}
