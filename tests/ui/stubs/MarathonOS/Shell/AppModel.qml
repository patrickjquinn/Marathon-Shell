pragma Singleton
import QtQml

QtObject {
    property var names: ({})
    property var icons: ({})
    signal modelReset
    signal dataChanged
    readonly property int count: Object.keys(names).length
    function findById(appId) {
        return names[appId] ? {
            name: names[appId],
            icon: icons[appId] || ""
        } : ({});
    }
}
