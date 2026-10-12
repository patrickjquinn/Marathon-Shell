import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../GalleryModel.js" as Model

Page {
    id: root

    property var photo

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            PageHeader { title: qsTr("Details") }
            DetailItem {
                objectName: "nameDetail"
                label: qsTr("Name")
                value: Model.fileName(root.photo)
            }
            DetailItem {
                objectName: "dateDetail"
                visible: root.photo.timestamp > 0
                label: qsTr("Date")
                value: Format.formatDate(new Date(root.photo.timestamp), Formatter.DateLong)
            }
            DetailItem {
                visible: root.photo.timestamp > 0
                label: qsTr("Time")
                value: Format.formatDate(new Date(root.photo.timestamp), Formatter.TimeValue)
            }
            DetailItem {
                objectName: "resolutionDetail"
                visible: root.photo.width > 0 && root.photo.height > 0
                label: qsTr("Resolution")
                value: qsTr("%1 × %2").arg(root.photo.width).arg(root.photo.height)
            }
            DetailItem {
                visible: !!root.photo.album
                label: qsTr("Album")
                value: root.photo.album || ""
            }
            DetailItem {
                objectName: "locationDetail"
                label: qsTr("Location")
                value: decodeURIComponent(String(root.photo.path).replace(/^file:\/\//, "").replace(/\/[^\/]*$/, ""))
            }
        }

        VerticalScrollDecorator {}
    }
}
