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

    CoverHeadline {
        objectName: "coverCount"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        visible: cover.count > 0
        value: cover.count
        label: cover.count === 1 ? qsTr("item") : qsTr("items")
    }

    CoverActionList {
        CoverAction {
            objectName: "addAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.addRequested()
        }
    }
}
