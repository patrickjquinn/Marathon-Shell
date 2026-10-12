import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

CoverBackground {
    id: cover

    property int count

    signal addRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.count === 0
        text: qsTr("No items")
    }

    Label {
        objectName: "coverCount"
        visible: cover.count > 0
        anchors.centerIn: parent
        text: cover.count === 1 ? qsTr("1 item") : qsTr("%1 items").arg(cover.count)
        font.pixelSize: Theme.fontSizeLarge
    }

    CoverActionList {
        CoverAction {
            objectName: "addAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.addRequested()
        }
    }
}
