pragma Singleton
import QtQml
QtObject {
    property bool isOnLockScreen: false
    function triggerUnlockAnimation() {}
    function triggerShakeAnimation() {}
}
