pragma Singleton
import QtQuick

QtObject {
    id: root

    // Backend is the C++ HapticManager singleton (from MarathonOS.Shell),
    // injected by the shell at startup. Typed as `var` rather than
    // QtObject so qmllint doesn't flag every duck-typed call — this is
    // deliberate cross-module layering: marathon-ui must not import
    // MarathonOS.Shell. The contract is documented here.
    property var backend: null

    readonly property bool enabled: backend ? backend.enabled : false

    readonly property real lightIntensity: 0.3
    readonly property real mediumIntensity: 0.6
    readonly property real heavyIntensity: 1

    readonly property int shortDuration: 10
    readonly property int mediumDuration: 20
    readonly property int longDuration: 40

    function light() {
        if (backend && backend.enabled)
            backend.light();
    }

    function lightImpact() {
        light();
    }

    function medium() {
        if (backend && backend.enabled)
            backend.medium();
    }

    function mediumImpact() {
        medium();
    }

    function heavy() {
        if (backend && backend.enabled)
            backend.heavy();
    }
    function heavyImpact() {
        heavy();
    }

    function selection() {
        light();
    }

    function selectionChanged() {
        light();
    }

    function impact(intensity, duration) {
        if (!backend || !backend.enabled)
            return;
        if (intensity >= heavyIntensity)
            backend.heavy();
        else if (intensity >= mediumIntensity)
            backend.medium();
        else
            backend.light();
    }

    function success() {
        light();
        Qt.callLater(light);
    }

    function error() {
        heavy();
    }

    function warning() {
        medium();
        Qt.callLater(medium);
    }
}
