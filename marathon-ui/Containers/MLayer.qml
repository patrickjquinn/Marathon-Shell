import QtQuick

Item {
    id: root

    property int zIndex: 0
    default property alias content: contentItem.data

    z: zIndex
    anchors.fill: parent

    Item {
        id: contentItem
        anchors.fill: parent
    }
}
