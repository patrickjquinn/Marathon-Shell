import QtCore
import QtQuick
import "../models"

// The real root, kept off the network and reading fixtures from data/.
StoreBackend {
    id: root

    property var opened: []

    // The fixtures predate the phone filter; its own tests turn it on.
    phoneOnly: false

    flathubApi: "http://127.0.0.1:9/flathub"
    odrsApi: "http://127.0.0.1:9/odrs"
    stateDir: Qt.resolvedUrl("data").toString().replace("file://", "")
    cacheFile: StandardPaths.writableLocation(StandardPaths.TempLocation) + "/marathon-store-test-" + Qt.md5(String(Math.random())) + ".ini"
    openExternally: url => root.opened = root.opened.concat([url])
}
