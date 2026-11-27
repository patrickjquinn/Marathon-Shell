import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("NFC")
            }
            TextSwitch {
                objectName: "nfcSwitch"
                text: qsTr("NFC")
                description: qsTr("Reads tags held to the back of the phone while the screen is on, and shows what they hold")
                automaticCheck: false
                checked: Settings.nfcEnabled
                onClicked: Settings.nfcEnabled = !checked
            }
        }
    }
}
