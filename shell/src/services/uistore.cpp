#include "uistore.h"
#include <QtGlobal>

UIStore::UIStore(QObject *parent)
    : QObject(parent) {}

void UIStore::setShellRef(QObject *shellRef) {
    if (m_shellRef == shellRef) {
        return;
    }
    m_shellRef = shellRef;
    emit shellRefChanged();
}

void UIStore::openSearch() {
    setSearchOpen(true);
}

void UIStore::closeSearch() {
    setSearchOpen(false);
}

void UIStore::toggleSearch() {
    if (m_searchOpen) {
        closeSearch();
    } else {
        openSearch();
    }
}

void UIStore::openShareSheet(const QVariant &content, const QString &contentType) {
    emit showShareSheet(content, contentType.isEmpty() ? QStringLiteral("text") : contentType);
    setShareSheetOpen(true);
}

void UIStore::closeShareSheet() {
    setShareSheetOpen(false);
}

void UIStore::openClipboardManager() {
    setClipboardManagerOpen(true);
}

void UIStore::closeClipboardManager() {
    setClipboardManagerOpen(false);
}

void UIStore::openQuickSettings() {
    setQuickSettingsOpen(true);
    if (m_shellRef) {
        QVariant heightValue = m_shellRef->property("maxQuickSettingsHeight");
        if (heightValue.isValid()) {
            setQuickSettingsHeight(heightValue.toDouble());
            return;
        }
    }
    setQuickSettingsHeight(1000.0);
}

void UIStore::closeQuickSettings() {
    setQuickSettingsOpen(false);
    setQuickSettingsHeight(0.0);
}

void UIStore::toggleQuickSettings() {
    if (m_quickSettingsOpen) {
        closeQuickSettings();
    } else {
        openQuickSettings();
    }
}

void UIStore::openApp(const QString &appId, const QString &appName, const QString &appIcon) {
    setCurrentAppId(appId);
    setCurrentAppName(appName);
    setCurrentAppIcon(appIcon);
    setAppWindowOpen(true);
    if (appId == QStringLiteral("settings")) {
        setSettingsOpen(true);
    }
}

void UIStore::openApp(const QVariant &appId, const QVariant &appName, const QVariant &appIcon) {
    openApp(appId.toString(), appName.toString(), appIcon.toString());
}

void UIStore::closeApp() {
    setAppWindowOpen(false);
    if (m_currentAppId == QStringLiteral("settings")) {
        setSettingsOpen(false);
    }
    setCurrentAppId(QString());
    setCurrentAppName(QString());
    setCurrentAppIcon(QString());
}

void UIStore::minimizeApp() {
    closeApp();
}

void UIStore::restoreApp(const QString &appId, const QString &appName, const QString &appIcon) {
    setAppWindowOpen(true);
    setCurrentAppName(appName);
    setCurrentAppIcon(appIcon);
    setCurrentAppId(appId);
    if (appId == QStringLiteral("settings")) {
        setSettingsOpen(true);
    }
}

void UIStore::restoreApp(const QVariant &appId, const QVariant &appName, const QVariant &appIcon) {
    restoreApp(appId.toString(), appName.toString(), appIcon.toString());
}

void UIStore::openSettings() {
    setSettingsOpen(true);
}

void UIStore::closeSettings() {
    setSettingsOpen(false);
}

void UIStore::minimizeSettings() {
    minimizeApp();
}

void UIStore::closeAll() {
    closeQuickSettings();
    closeApp();
    closeSettings();
    closeSearch();
    closeShareSheet();
    closeClipboardManager();
}

void UIStore::setQuickSettingsOpen(bool open) {
    if (m_quickSettingsOpen == open) {
        return;
    }
    m_quickSettingsOpen = open;
    emit quickSettingsOpenChanged();
}

void UIStore::setQuickSettingsHeight(double height) {
    if (qFuzzyCompare(m_quickSettingsHeight, height)) {
        return;
    }
    m_quickSettingsHeight = height;
    emit quickSettingsHeightChanged();
}

void UIStore::setQuickSettingsDragging(bool dragging) {
    if (m_quickSettingsDragging == dragging) {
        return;
    }
    m_quickSettingsDragging = dragging;
    emit quickSettingsDraggingChanged();
}

void UIStore::setAppWindowOpen(bool open) {
    if (m_appWindowOpen == open) {
        return;
    }
    m_appWindowOpen = open;
    emit appWindowOpenChanged();
}

void UIStore::setCurrentAppId(const QString &appId) {
    if (m_currentAppId == appId) {
        return;
    }
    m_currentAppId = appId;
    emit currentAppIdChanged();
}

void UIStore::setCurrentAppName(const QString &appName) {
    if (m_currentAppName == appName) {
        return;
    }
    m_currentAppName = appName;
    emit currentAppNameChanged();
}

void UIStore::setCurrentAppIcon(const QString &appIcon) {
    if (m_currentAppIcon == appIcon) {
        return;
    }
    m_currentAppIcon = appIcon;
    emit currentAppIconChanged();
}

void UIStore::setSettingsOpen(bool open) {
    if (m_settingsOpen == open) {
        return;
    }
    m_settingsOpen = open;
    emit settingsOpenChanged();
}

void UIStore::setSearchOpen(bool open) {
    if (m_searchOpen == open) {
        return;
    }
    m_searchOpen = open;
    emit searchOpenChanged();
}

void UIStore::setShareSheetOpen(bool open) {
    if (m_shareSheetOpen == open) {
        return;
    }
    m_shareSheetOpen = open;
    emit shareSheetOpenChanged();
}

void UIStore::setClipboardManagerOpen(bool open) {
    if (m_clipboardManagerOpen == open) {
        return;
    }
    m_clipboardManagerOpen = open;
    emit clipboardManagerOpenChanged();
}
