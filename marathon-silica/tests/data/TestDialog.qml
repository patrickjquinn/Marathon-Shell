import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    property bool ok: true
    canAccept: ok
    DialogHeader {
        title: "Rename"
    }
}
