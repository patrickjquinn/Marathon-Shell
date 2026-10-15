import QtQuick
import Keel 1.0
import Nemo.Configuration 1.0

// Turns the wallpaper seed into a Keel ambience with Keel's own palette rule,
// applies it to the shell's engine and publishes it for apps.
QtObject {
    id: root

    property var service
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

    // Keel's pickers and time formats read Sailfish's 24-hour key from dconf.
    property ConfigurationValue _timeFormat24: ConfigurationValue {
        key: "/sailfish/i18n/lc_timeformat24h"
    }

    property Connections _timeFormat: Connections {
        function onTimeFormatChanged() {
            root.publishTimeFormat();
        }

        target: root.settings
    }

    function keelTimeFormat(format) {
        return format === "12h" ? "12" : "24";
    }

    function publishTimeFormat() {
        if (settings && settings.timeFormat !== undefined)
            _timeFormat24.value = keelTimeFormat(settings.timeFormat);
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
        return map;
    }

    function apply() {
        if (!service || !service.baseColor.valid)
            return;
        const map = buildMap();
        Ambience.applyForwarded(Object.keys(map).map(k => k + "=" + map[k]).join("\n"));
        service.publish(map);
    }

    Component.onCompleted: {
        apply();
        publishTimeFormat();
    }
}
