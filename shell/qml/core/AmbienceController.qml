import QtQuick
import Keel 1.0

// Turns the wallpaper seed into a Keel ambience with Keel's own palette rule,
// applies it to the shell's engine and publishes it for apps.
QtObject {
    id: root

    property var service

    property Connections _seed: Connections {
        function onSeedChanged() {
            root.apply();
        }

        target: root.service
    }

    function buildMap() {
        const scheme = service.light ? 1 : 0;
        return {
            "/desktop/jolla/theme/color/highlight": Ambience.highlightFromColor(service.baseColor, scheme),
            "/desktop/jolla/theme/color_scheme": service.light ? "darkonlight" : "lightondark",
            "/desktop/jolla/theme/wallpaper": service.wallpaperUrl
        };
    }

    function apply() {
        if (!service || !service.baseColor.valid)
            return;
        const map = buildMap();
        Ambience.applyForwarded(Object.keys(map).map(k => k + "=" + map[k]).join("\n"));
        service.publish(map);
    }

    Component.onCompleted: apply()
}
