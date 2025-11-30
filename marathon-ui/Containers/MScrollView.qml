import QtQuick

Flickable {
    id: root

    default property alias content: contentContainer.data

    contentHeight: contentContainer.height
    clip: true

    flickDeceleration: 5000
    maximumFlickVelocity: 2500
    boundsBehavior: Flickable.DragAndOvershootBounds

    Column {
        id: contentContainer
        width: parent.width
    }
}
