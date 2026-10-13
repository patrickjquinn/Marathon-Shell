import QtQuick
import Keel 1.0

// Turns the wallpaper seed into a Keel ambience with Keel's own palette rule,
// applies it to the shell's engine and publishes it for apps.
QtObject {
    id: root

    property var service
    // Keel scales text by the font multiplier, so Keel apps' text follows
    // Interface size, live.
    property var settings

    property Connections _seed: Connections {
        function onSeedChanged() {
            root.apply();
        }

        function onPixelRatioChanged() {
            root.apply();
        }

        target: root.service
    }

    property Connections _settings: Connections {
        function onUserScaleFactorChanged() {
            root.apply();
        }

        target: root.settings
    }

    function buildMap() {
        const scheme = service.light ? 1 : 0;
        const map = {
            "/desktop/jolla/theme/color/highlight": Ambience.highlightFromColor(service.baseColor, scheme),
            "/desktop/jolla/theme/color_scheme": service.light ? "darkonlight" : "lightondark",
            "/desktop/jolla/theme/wallpaper": service.wallpaperUrl
        };
        if (service.pixelRatio > 0)
            map["/desktop/sailfish/silica/theme_pixel_ratio"] = service.pixelRatio;
        if (settings && settings.userScaleFactor > 0)
            map["/desktop/jolla/theme/font/sizeMultiplier"] = settings.userScaleFactor;
        return map;
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
