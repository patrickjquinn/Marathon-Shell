pragma Singleton
import QtQml
QtObject {
    property var opened: []
    property bool clipboardManagerOpen: false
    function closeClipboardManager() { clipboardManagerOpen = false; }
    property bool quickSettingsOpen: false
    property real quickSettingsHeight: 0
    property bool quickSettingsDragging: false
    property bool searchOpen: false
    property bool appWindowOpen: false
    property bool settingsOpen: false
    property var shellRef: null
    function openQuickSettings() { quickSettingsOpen = true; quickSettingsHeight = shellRef ? shellRef.maxQuickSettingsHeight : 1000; }
    function closeQuickSettings() { quickSettingsOpen = false; quickSettingsHeight = 0; }
    function closeSearch() { searchOpen = false; }
    function openApp(appId, name, icon) { opened = opened.concat([appId]); }
}
