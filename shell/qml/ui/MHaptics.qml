pragma Singleton
import QtQuick

QtObject {
    id: root

    // Backend is the C++ HapticManager, injected by the shell at startup.
    property var backend: null

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
}
