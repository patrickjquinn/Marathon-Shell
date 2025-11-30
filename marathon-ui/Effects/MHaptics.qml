pragma Singleton
import QtQuick

QtObject {
    id: root

    // Haptic feedback intensity levels (0.0 - 1.0)
    readonly property real lightIntensity: 0.3
    readonly property real mediumIntensity: 0.6
    readonly property real heavyIntensity: 1.0

    // Haptic feedback durations (ms)
    readonly property int shortDuration: 10
    readonly property int mediumDuration: 20
    readonly property int longDuration: 40

    // Enable/disable haptics globally
    property bool enabled: true

    /**
     * Light haptic feedback
     * Use for: Buttons, toggles, selection changes
     */
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

    /**
     * Medium haptic feedback
     * Use for: Confirmations, important actions, slider steps
     */
    function medium() {
        if (!enabled)
            return;
        console.log("[Haptics] Medium tap");
    }

    /**
     * Heavy haptic feedback
     * Use for: Errors, critical actions, notifications
     */
    function heavy() {
        if (!enabled)
            return;
        console.log("[Haptics] Heavy tap");
    }

    /**
     * Selection feedback (light, rapid)
     * Use for: Scrolling through picker items, scrubbing sliders
     */
    function selection() {
        if (!enabled)
            return;
        console.log("[Haptics] Selection");
    }

    /**
     * Impact feedback with custom intensity
     * @param intensity: 0.0 - 1.0
     * @param duration: milliseconds
     */
    function impact(intensity, duration) {
        if (!enabled)
            return;
        console.log("[Haptics] Impact - intensity:", intensity, "duration:", duration);
    }

    /**
     * Success pattern (double light tap)
     * Use for: Successful operations, confirmations
     */
    function success() {
        if (!enabled)
            return;
        light();
        Qt.callLater(function () {
            Qt.callLater(light);
        });
    }

    /**
     * Error pattern (long heavy vibration)
     * Use for: Failed operations, invalid input
     */
    function error() {
        if (!enabled)
            return;
        impact(heavyIntensity, longDuration);
    }

    /**
     * Warning pattern (two medium taps)
     * Use for: Warnings, important notices
     */
    function warning() {
        if (!enabled)
            return;
        medium();
        Qt.callLater(function () {
            Qt.callLater(medium);
        });
    }
}
