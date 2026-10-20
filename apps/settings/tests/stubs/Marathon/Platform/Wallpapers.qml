pragma Singleton
import QtQml

QtObject {
    property var wallpapers: [
        { name: "Slate Aurora", path: "file:///wallpapers/slate-aurora.svg", isDark: true },
        { name: "Dawn", path: "file:///wallpapers/dawn.svg", isDark: false }
    ]
}
