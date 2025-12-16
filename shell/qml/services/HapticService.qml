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
    // no-op

    id: hapticService

    /**
     * @brief Whether haptic feedback is available on this platform
     * @type {bool}
     * @readonly
     */
    readonly property bool isAvailable: (typeof HapticManager !== "undefined" && HapticManager) ? HapticManager.available : false
    /**
     * @brief Whether haptic feedback is enabled (user preference)
     * @type {bool}
     * @default true
     */
    property bool enabled: (typeof HapticManager !== "undefined" && HapticManager) ? HapticManager.enabled : false
    property Binding enabledBinding

    enabledBinding: Binding {
        target: typeof HapticManager !== "undefined" ? HapticManager : null
        property: "enabled"
        value: hapticService.enabled
        when: typeof HapticManager !== "undefined" && HapticManager
        restoreMode: Binding.RestoreBinding
    }

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

        if (typeof HapticManager !== "undefined" && HapticManager)
            HapticManager.vibratePatternVariant(durations);
    }

    /**
     * @brief Vibrate with a repeating pattern
     * @param {Array<int>} pattern - [vibrate_ms, pause_ms]
     * @param {int} repeat - Number of repetitions (-1 for infinite)
     */
    function vibratePattern(durations, repeat) {
        if (!enabled || !isAvailable)
            return;

        // repeat is currently ignored; the backend supports a single finite pattern.
        if (typeof HapticManager !== "undefined" && HapticManager)
            HapticManager.vibratePatternVariant(durations);
    }

    /**
     * @brief Stop any ongoing vibration
     */
    function stopVibration() {
        if (!isAvailable)
            return;

        if (typeof HapticManager !== "undefined" && HapticManager)
            HapticManager.cancelVibration();
    }

    function vibrate(duration) {
        if (!enabled || !isAvailable)
            return;

        if (typeof HapticManager !== "undefined" && HapticManager)
            HapticManager.vibrate(duration);
    }

    Component.onCompleted: {}
}
