import QtQuick
import "../models"

// The real root, kept off the network and reading fixtures from data/.
StoreBackend {
    id: root

    property var opened: []

    flathubApi: "http://127.0.0.1:9/flathub"
    odrsApi: "http://127.0.0.1:9/odrs"
    stateDir: Qt.resolvedUrl("data").toString().replace("file://", "")
    openExternally: url => root.opened = root.opened.concat([url])
}
