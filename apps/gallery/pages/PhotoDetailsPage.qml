import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

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
                objectName: "pathDetail"
                label: qsTr("File path")
                value: decodeURIComponent(String(root.photo.path).replace(/^file:\/\//, ""))
                alignment: Qt.AlignLeft
                forceValueBelow: true
            }
            DetailItem {
                objectName: "resolutionDetail"
                visible: root.photo.width > 0 && root.photo.height > 0
                label: qsTr("Size")
                value: qsTr("%1 × %2").arg(root.photo.width).arg(root.photo.height)
                alignment: Qt.AlignLeft
            }
            DetailItem {
                objectName: "dateDetail"
                visible: root.photo.timestamp > 0
                label: qsTr("Date")
                value: qsTr("%1, %2").arg(Format.formatDate(new Date(root.photo.timestamp), Formatter.TimeValue))
                                     .arg(Qt.formatDate(new Date(root.photo.timestamp), Locale.ShortFormat))
                alignment: Qt.AlignLeft
            }
            DetailItem {
                visible: !!root.photo.album
                label: qsTr("Album")
                value: root.photo.album || ""
                alignment: Qt.AlignLeft
            }
        }

        VerticalScrollDecorator {}
    }
}
