pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: uiStore

    property bool quickSettingsOpen: false
    property real quickSettingsHeight: 0
    property bool quickSettingsDragging: false

    property bool appWindowOpen: false
    property string currentAppId: ""
    property string currentAppName: ""
    property string currentAppIcon: ""

    property bool settingsOpen: false

    property bool searchOpen: false
    property bool shareSheetOpen: false
    property bool clipboardManagerOpen: false

    signal showNotificationToast(var notification)
    signal showSystemHUD(string type, real value)
    signal showConfirmDialog(string title, string message, var onConfirm)
    signal showShareSheet(var content, string contentType)

    function openSearch() {
        searchOpen = true;
        Logger.state("UIStore", "search closed", "open");
    }

    function closeSearch() {
        searchOpen = false;
        Logger.state("UIStore", "search open", "closed");
    }

    function toggleSearch() {
        if (searchOpen) {
            closeSearch();
        } else {
            openSearch();
        }
    }

    function openShareSheet(content, contentType) {
        showShareSheet(content, contentType || "text");
        shareSheetOpen = true;
    }

    function closeShareSheet() {
        shareSheetOpen = false;
    }

    function openClipboardManager() {
        clipboardManagerOpen = true;
    }

    function closeClipboardManager() {
        clipboardManagerOpen = false;
    }

    property var shellRef: null  // Reference to shell for dynamic sizing

    function openQuickSettings() {
        quickSettingsOpen = true;
        if (shellRef) {
            quickSettingsHeight = shellRef.maxQuickSettingsHeight;
        } else {
            quickSettingsHeight = 1000;  // Fallback
        }
        Logger.state("UIStore", "quickSettings closed", "open");
    }

    function closeQuickSettings() {
        quickSettingsOpen = false;
        quickSettingsHeight = 0;
        Logger.state("UIStore", "quickSettings open", "closed");
    }

    function toggleQuickSettings() {
        if (quickSettingsOpen) {
            closeQuickSettings();
        } else {
            openQuickSettings();
        }
    }

    function openApp(appId, appName, appIcon) {
        currentAppId = appId;
        currentAppName = appName;
        currentAppIcon = appIcon;
        appWindowOpen = true;

        // Also set settingsOpen for Settings app (for layout decisions)
        if (appId === "settings") {
            settingsOpen = true;
        }
    }

    function closeApp() {
        appWindowOpen = false;

        // Also clear settingsOpen if it was Settings
        if (currentAppId === "settings") {
            settingsOpen = false;
        }

        currentAppId = "";
        currentAppName = "";
        currentAppIcon = "";
    }

    function minimizeApp() {
        appWindowOpen = false;

        // Also clear settingsOpen if it was Settings
        if (currentAppId === "settings") {
            settingsOpen = false;
        }

        // CRITICAL: Clear currentAppId so restoring the same app later triggers onCurrentAppIdChanged
        currentAppId = "";
        currentAppName = "";
        currentAppIcon = "";
    }

    function restoreApp(appId, appName, appIcon) {
        // CRITICAL: Set appWindowOpen BEFORE currentAppId so signal handlers see correct state
        appWindowOpen = true;
        currentAppName = appName;
        currentAppIcon = appIcon;
        currentAppId = appId;  // Set last so onCurrentAppIdChanged fires with appWindowOpen=true

        // Also set settingsOpen for Settings app
        if (appId === "settings") {
            settingsOpen = true;
        }
    }

    function openSettings() {
        settingsOpen = true;
        Logger.state("UIStore", "settings closed", "open");
    }

    function closeSettings() {
        settingsOpen = false;
        Logger.state("UIStore", "settings open", "closed");
    }

    function minimizeSettings() {
        settingsOpen = false;
    }

    function closeAll() {
        closeQuickSettings();
        closeApp();
        closeSettings();
        closeSearch();
        closeShareSheet();
        closeClipboardManager();
    }
}
