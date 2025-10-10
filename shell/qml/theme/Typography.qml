pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: Qt.platform.os === "osx" ? 
        ".AppleSystemUIFont" : "Roboto"
    readonly property int sizeXLarge: 48
    readonly property int sizeLarge: 36
    readonly property int sizeBody: 28
    readonly property int sizeSmall: 24
    readonly property int sizeXSmall: 20
    readonly property int weightBold: Font.Bold
    readonly property int weightMedium: Font.DemiBold
}

