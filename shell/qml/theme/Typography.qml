pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: Qt.platform.os === "osx" ? 
        ".AppleSystemUIFont" : "Roboto"
    readonly property int sizeXLarge: 28
    readonly property int sizeLarge: 20
    readonly property int sizeBody: 16
    readonly property int sizeSmall: 14
    readonly property int sizeXSmall: 12
    readonly property int weightBold: Font.Bold
    readonly property int weightMedium: Font.DemiBold
}

