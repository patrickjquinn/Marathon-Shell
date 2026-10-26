pragma Singleton
import QtQml
QtObject {
    property string wallpaperUrl: ""
    property bool light: false
    property var wallpapers: [
        { name: "Moos Sunset", path: Qt.resolvedUrl("../../../../../shell/resources/wallpapers/moos-sunset.jpg") },
        { name: "Meridian", path: Qt.resolvedUrl("../../../../../shell/resources/wallpapers/meridian.jpg") }
    ]
}
