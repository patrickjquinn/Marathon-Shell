pragma Singleton
import QtQml
QtObject {
    property bool isOnLockScreen: false
    property bool isLocked: false
    property bool showLockScreen: false
    function showLock() { showLockScreen = true; }
    function triggerUnlockAnimation() {}
    function triggerShakeAnimation() {}
}
