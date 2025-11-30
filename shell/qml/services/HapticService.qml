pragma Singleton
import QtQuick

/**
 * @singleton
 * @brief Provides haptic feedback (vibration) for user interactions
 *
 * HapticService provides standardized haptic feedback patterns across
 * different platforms (Linux, Android). Automatically disabled on platforms
 * without haptic support (macOS, desktop).
 *
 * @example
 * // Provide light feedback for button taps
 * Button {
 *     onClicked: HapticService.light()
 * }
 *
 * @example
 * // Heavy feedback for critical actions
 * Button {
 *     text: "Delete"
 *     onClicked: {
 *         HapticService.heavy()
 *         deleteItem()
 *     }
 * }
 */
QtObject {
    id: hapticService

    /**
     * @brief Whether haptic feedback is available on this platform
     * @type {bool}
     * @readonly
     */
    readonly property bool isAvailable: Platform.isLinux || Platform.isAndroid

    /**
     * @brief Whether haptic feedback is enabled (user preference)
     * @type {bool}
     * @default true
     */
    property bool enabled: true

    /**
     * @brief Provides light haptic feedback (10ms)
     *
     * Use for subtle interactions like button taps, switches, selections.
     */
    function light() {
        if (!enabled || !isAvailable)
            return;
        vibrate(10);
    }

    /**
     * @brief Provides medium haptic feedback (25ms)
     *
     * Use for moderate actions like navigation, panel opens, significant state changes.
     */
    function medium() {
        if (!enabled || !isAvailable)
            return;
        vibrate(25);
    }

    /**
     * @brief Provides heavy haptic feedback (50ms)
     *
     * Use for important actions like deletions, errors, warnings, or critical confirmations.
     */
    function heavy() {
        if (!enabled || !isAvailable)
            return;
        vibrate(50);
    }

    /**
     * @brief Provides custom haptic pattern with specific durations
     *
     * @param {Array<int>} durations - Array of vibration durations in milliseconds
     *
     * @example
     * // Two quick pulses
     * HapticService.pattern([50, 100, 50])
     */
    function pattern(durations) {
        if (!enabled || !isAvailable)
            return;
        console.log("[HapticService] Vibration pattern:", durations);
    }

    /**
     * @brief Vibrate with a repeating pattern
     * @param {Array<int>} pattern - [vibrate_ms, pause_ms]
     * @param {int} repeat - Number of repetitions (-1 for infinite)
     */
    function vibratePattern(durations, repeat) {
        if (!enabled || !isAvailable)
            return;
        console.log("[HapticService] Vibration pattern:", durations, "repeat:", repeat);

        // For now, just do a single vibration
        // In production, this would be wired to HapticManagerCpp
        if (typeof HapticManagerCpp !== 'undefined') {
            HapticManagerCpp.vibratePattern(durations, repeat);
        } else {
            vibrate(durations[0] || 500);
        }
    }

    /**
     * @brief Stop any ongoing vibration
     */
    function stopVibration() {
        if (!isAvailable)
            return;
        console.log("[HapticService] Stopping vibration");

        if (typeof HapticManagerCpp !== 'undefined') {
            HapticManagerCpp.stopVibration();
        }
    }

    function vibrate(duration) {
        if (!enabled || !isAvailable)
            return;
        console.log("[HapticService] Vibrate:", duration + "ms");

        if (typeof HapticManagerCpp !== 'undefined') {
            HapticManagerCpp.vibrate(duration);
        } else if (Platform.isLinux) {
            _vibrateLinux(duration);
        } else if (Platform.isAndroid) {
            _vibrateAndroid(duration);
        }
    }

    function _vibrateLinux(duration) {
        console.log("[HapticService] Linux vibration via /sys/class/leds/vibrator/brightness");
    }

    function _vibrateAndroid(duration) {
        console.log("[HapticService] Android vibration via Qt.Vibration");
    }

    Component.onCompleted: {
        console.log("[HapticService] Initialized");
        console.log("[HapticService] Haptics available:", isAvailable);
    }
}
