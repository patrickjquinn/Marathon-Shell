import MarathonOS.Shell
import QtQuick
import QtQuick.Effects

// One frosted copy of the wallpaper that every MGlassPlatter on a page
// samples by screen position: a single small blur, redone only when the
// wallpaper changes, instead of a blur per card. Fill the screen with it.
Item {
    id: root

    readonly property alias texture: frosted

    Image {
        id: wallpaper

        anchors.fill: parent
        source: SettingsManagerCpp.wallpaperPath
        sourceSize: Qt.size(Math.max(1, Math.round(root.width / 6)), Math.max(1, Math.round(root.height / 6)))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        id: blurred

        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: !MMotion.reduceBlur
        blur: 1.0
        blurMax: 32
        saturation: 0.3
        brightness: -0.02
        visible: false
    }

    ShaderEffectSource {
        id: frosted

        anchors.fill: parent
        sourceItem: blurred
        hideSource: true
        textureSize: Qt.size(Math.max(1, Math.round(root.width / 4)), Math.max(1, Math.round(root.height / 4)))
        visible: false
    }
}
