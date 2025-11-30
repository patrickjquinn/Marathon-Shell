import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: toolBar

    signal clipboardClicked
    signal emojiClicked
    signal settingsClicked
    signal dismissClicked

    Row {
        anchors.centerIn: parent
        spacing: Math.round(24 * Constants.scaleFactor)

        // Clipboard
        ToolButton {
            iconName: "file-text" // Available icon
            onClicked: toolBar.clipboardClicked()
        }

        // Emoji Search (Quick Access)
        ToolButton {
            iconName: "star" // Available icon
            onClicked: toolBar.emojiClicked()
        }

        // Settings
        ToolButton {
            iconName: "settings"
            onClicked: toolBar.settingsClicked()
        }

        // Dismiss Keyboard
        ToolButton {
            iconName: "chevron-down"
            onClicked: toolBar.dismissClicked()
        }
    }

    component ToolButton: AbstractButton {
        property string iconName: ""

        width: Math.round(40 * Constants.scaleFactor)
        height: Math.round(30 * Constants.scaleFactor)

        background: Rectangle {
            color: parent.pressed ? "#33ffffff" : "transparent"
            radius: 4
        }

        contentItem: Item {
            Image {
                anchors.centerIn: parent
                source: "qrc:/images/icons/lucide/" + parent.parent.iconName + ".svg"
                width: Math.round(20 * Constants.scaleFactor)
                height: width
                sourceSize.width: width
                sourceSize.height: height
                opacity: 0.9

                // Tint the icon white using a simple shader effect if ColorOverlay isn't available
                // Or simpler: use layer.effect with a ColorOverlay if we can import it.
                // But since we don't know if GraphicalEffects is linked, let's try a simpler approach:
                // Use QtQuick.Controls.IconLabel or similar?
                // Actually, let's just use a ShaderEffect to colorize it white.

                layer.enabled: true
                layer.effect: ShaderEffect {
                    property color color: "white"
                    fragmentShader: "
                        uniform lowp sampler2D source;
                        uniform lowp vec4 color;
                        varying highp vec2 qt_TexCoord0;
                        void main() {
                            lowp vec4 tex = texture2D(source, qt_TexCoord0);
                            gl_FragColor = vec4(color.rgb, tex.a * color.a);
                        }
                    "
                }
            }
        }

        onClicked: {
            HapticService.light();
        }
    }
}
