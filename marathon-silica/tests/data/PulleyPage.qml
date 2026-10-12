import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    property var log: []
    SilicaListView {
        objectName: "view"
        anchors.fill: parent
        model: 0
        PullDownMenu {
            MenuItem { text: "New"; onClicked: log.push("new") }
        }
    }
}
