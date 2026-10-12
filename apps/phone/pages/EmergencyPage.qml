import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: root

    property var phone

    PageHeader {
        id: header

        title: qsTr("Emergency call")
    }

    DialerPanel {
        objectName: "dialer"
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        phone: root.phone
    }
}
