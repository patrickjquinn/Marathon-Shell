pragma Singleton
import QtQml
QtObject {
    readonly property real scaleFactor: 1
    readonly property real screenWidth: 360
    readonly property real screenHeight: 1140
    readonly property bool isSquareScreen: false
    readonly property real statusBarHeight: 32
    readonly property real navBarHeight: 40
    readonly property real bottomBarHeight: 44
    readonly property real safeAreaTop: 0
    readonly property real safeAreaLeft: 0
    readonly property real safeAreaRight: 0
    readonly property int zIndexBackground: 0
    readonly property int zIndexLockScreen: 1000
    readonly property int zIndexModalOverlay: 2000
}
