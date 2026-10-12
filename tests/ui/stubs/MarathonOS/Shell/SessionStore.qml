pragma Singleton
import QtQml
QtObject {
    property bool isOnLockScreen: false
    property bool isLocked: false
    function triggerUnlockAnimation() {}
    function triggerShakeAnimation() {}
}
