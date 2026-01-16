pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property real lightIntensity: 0.3
    readonly property real mediumIntensity: 0.6
    readonly property real heavyIntensity: 1

    readonly property int shortDuration: 10
    readonly property int mediumDuration: 20
    readonly property int longDuration: 40

    property bool enabled: false

    function light() {
        if (!enabled)
            return;

        console.log("[Haptics] Light tap");
    }

    function lightImpact() {
        light();
    }

    function selectionChanged() {
        selection();
    }

    function medium() {
        if (!enabled)
            return;

        console.log("[Haptics] Medium tap");
    }

    function mediumImpact() {
        medium();
    }

    function heavy() {
        if (!enabled)
            return;

        console.log("[Haptics] Heavy tap");
    }

    function selection() {
        if (!enabled)
            return;

        console.log("[Haptics] Selection");
    }

    function impact(intensity, duration) {
        if (!enabled)
            return;

        console.log("[Haptics] Impact - intensity:", intensity, "duration:", duration);
    }

    function success() {
        if (!enabled)
            return;

        light();
        Qt.callLater(function () {
            Qt.callLater(light);
        });
    }

    function error() {
        if (!enabled)
            return;

        impact(heavyIntensity, longDuration);
    }

    function warning() {
        if (!enabled)
            return;

        medium();
        Qt.callLater(function () {
            Qt.callLater(medium);
        });
    }
}
