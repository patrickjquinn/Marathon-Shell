import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent

        PageHeader {
            title: qsTr("Mobile network")
        }
        ViewPlaceholder {
            objectName: "placeholder"
            enabled: true
            text: qsTr("Mobile network settings aren't available yet")
            hintText: qsTr("Turn mobile data on or off from the top menu")
        }
    }
}
