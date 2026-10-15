import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    property alias flickable: flick

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height
        Column {
            id: column
            width: parent.width
            DialogHeader { acceptText: "Save" }
            Item { width: 1; height: 3000 }
        }
    }
}
