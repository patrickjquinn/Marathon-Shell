pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: Qt.platform.os === "osx" ? ".AppleSystemUIFont" : "Roboto"
    
    readonly property int sizeDisplay: 32
    readonly property int sizeXLarge: 28
    readonly property int sizeLarge: 20
    readonly property int sizeBody: 16
    readonly property int sizeSmall: 14
    readonly property int sizeXSmall: 12
    readonly property int sizeTiny: 10
    
    readonly property int weightBlack: Font.Black
    readonly property int weightBold: Font.Bold
    readonly property int weightDemiBold: Font.DemiBold
    readonly property int weightMedium: Font.Medium
    readonly property int weightNormal: Font.Normal
    readonly property int weightLight: Font.Light
}

