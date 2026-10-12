import QtQml

QtObject {
    property real totalSpace: 64e9
    property real availableSpace: 24e9
    readonly property real usedSpace: totalSpace - availableSpace
    readonly property real usedPercentage: usedSpace / totalSpace * 100
    property string totalSpaceString: "64.0 GB"
    property string availableSpaceString: "24.0 GB"
    property string usedSpaceString: "40.0 GB"

    function refresh() {
    }
}
