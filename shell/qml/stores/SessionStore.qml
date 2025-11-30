pragma Singleton
import QtQuick

/**
 * @singleton
 * @brief Manages session lock state and transitions
 *
 * Tracks whether the session is locked and coordinates lock/unlock
 * animations across the UI (status bar lock icon, lock screen, etc.)
 */
QtObject {
    id: sessionStore

    // ===== SESSION STATE =====

    /**
     * @brief Whether the session is currently locked
     * @type {bool}
     * @default true
     */
    property bool isLocked: true

    /**
     * @brief Whether we're currently viewing the lock screen
     * Used to show lock icon in status bar
     * @type {bool}
     * @default false
     */
    property bool isOnLockScreen: false

    /**
     * @brief Whether the lock screen should be visible
     * True when session is locked OR when returning from screen-off with valid grace period
     * @type {bool}
     * @default true
     */
    property bool showLockScreen: true

    // ===== ANIMATION STATE =====

    /**
     * @brief Whether a lock state transition animation is in progress
     * @type {bool}
     * @default false
     */
    property bool isAnimatingLock: false

    /**
     * @brief Current lock transition direction
     * @type {string}
     * @values "locking" | "unlocking" | ""
     */
    property string lockTransition: ""

    /**
     * @brief Timestamp until which session is valid (grace period)
     * @type {number}
     * @private
     */
    property real sessionValidUntil: 0

    // ===== SIGNALS =====

    /**
     * @brief Emitted when lock state is about to change
     * @param {bool} toLocked - Target lock state
     */
    signal lockStateChanging(bool toLocked)

    /**
     * @brief Emitted when lock state has changed (after animation)
     * @param {bool} isLocked - New lock state
     */
    signal lockStateChanged(bool isLocked)

    /**
     * @brief Trigger shake animation on lock icon (invalid PIN)
     */
    signal triggerShakeAnimation

    /**
     * @brief Trigger unlock animation on lock icon (valid PIN)
     */
    signal triggerUnlockAnimation

    // ===== PUBLIC API =====

    /**
     * @brief Lock the session with animation
     */
    function lock() {
        console.log("[SessionStore] lock() called - current isLocked:", isLocked, "showLockScreen:", showLockScreen);
        if (isLocked) {
            console.log("[SessionStore] Already locked, ignoring");
            return;
        }

        console.log("[SessionStore] Locking session...");
        showLockScreen = true;  // Show lock screen when locking
        console.log("[SessionStore] Set showLockScreen to true");
        lockTransition = "locking";
        isAnimatingLock = true;
        lockStateChanging(true);

        // Complete animation after 300ms
        lockTimer.interval = 300;
        lockTimer.targetLocked = true;
        lockTimer.restart();
    }

    /**
     * @brief Unlock the session with animation
     */
    function unlock() {
        console.log("[SessionStore] unlock() called - current isLocked:", isLocked);
        if (!isLocked) {
            console.log("[SessionStore] Already unlocked, ignoring");
            return;
        }

        console.log("[SessionStore] Unlocking session...");
        showLockScreen = false;  // Hide lock screen when unlocking
        lockTransition = "unlocking";
        isAnimatingLock = true;
        lockStateChanging(false);

        // Mark session as valid for 5 minutes (grace period)
        sessionValidUntil = Date.now() + (5 * 60 * 1000);
        console.log("[SessionStore] Grace period set until:", new Date(sessionValidUntil).toLocaleTimeString());

        // Complete animation after 300ms
        lockTimer.interval = 300;
        lockTimer.targetLocked = false;
        lockTimer.restart();
    }

    /**
     * @brief Check if current session is still valid (grace period)
     * @returns {bool} True if session valid, false if PIN required
     */
    function checkSession() {
        // Grace period: unlock without PIN if < 5 minutes since last unlock
        var now = Date.now();
        var isValid = sessionValidUntil > now;

        if (!isValid) {
            console.log("[SessionStore] Session expired, PIN required");
        }

        return isValid;
    }

    /**
     * @brief Show lock screen (without locking session)
     * Used when returning from screen-off with valid grace period
     */
    function showLock() {
        console.log("[SessionStore] Showing lock screen (session may still be unlocked)");
        showLockScreen = true;
    }

    // ===== INTERNAL =====

    property Timer lockTimer: Timer {
        property bool targetLocked: true

        onTriggered: {
            console.log("[SessionStore] Lock transition complete - setting isLocked to:", targetLocked);
            isLocked = targetLocked;
            console.log("[SessionStore] isLocked is now:", isLocked);
            isAnimatingLock = false;
            lockTransition = "";
            lockStateChanged(isLocked);
        }
    }

    Component.onCompleted: {
        console.log("[SessionStore] Initialized - session locked by default");
    }
}
