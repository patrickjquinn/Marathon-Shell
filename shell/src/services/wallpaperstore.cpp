#include "wallpaperstore.h"
#include "src/managers/settingsmanager.h"
#include <QVariant>
#include <QVariantMap>

WallpaperStore::WallpaperStore(SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , m_settingsManager(settingsManager) {
    m_wallpapers = {
        QVariantMap{
            {"name", "Gradient 1"},
            {"path", resolveAssetPath("wallpapers/wallpaper.jpg", "qrc:/wallpapers/wallpaper.jpg")},
            {"isDark", true}},
        QVariantMap{
            {"name", "Gradient 2"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper2.jpg", "qrc:/wallpapers/wallpaper2.jpg")},
            {"isDark", true}},
        QVariantMap{
            {"name", "Gradient 3"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper3.jpg", "qrc:/wallpapers/wallpaper3.jpg")},
            {"isDark", true}},
        QVariantMap{
            {"name", "Gradient 4"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper4.jpg", "qrc:/wallpapers/wallpaper4.jpg")},
            {"isDark", false}},
        QVariantMap{
            {"name", "Gradient 5"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper5.jpg", "qrc:/wallpapers/wallpaper5.jpg")},
            {"isDark", true}},
        QVariantMap{
            {"name", "Gradient 6"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper6.jpg", "qrc:/wallpapers/wallpaper6.jpg")},
            {"isDark", false}},
        QVariantMap{
            {"name", "Gradient 7"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper7.jpg", "qrc:/wallpapers/wallpaper7.jpg")},
            {"isDark", true}},
        QVariantMap{
            {"name", "Gradient 8"},
            {"path",
             resolveAssetPath("wallpapers/wallpaper8.jpg", "qrc:/wallpapers/wallpaper8.jpg")},
            {"isDark", true}}};
    emit wallpapersChanged();

    if (m_settingsManager && !m_settingsManager->wallpaperPath().isEmpty()) {
        setCurrentWallpaper(m_settingsManager->wallpaperPath());
    } else {
        refreshIsDark();
    }

    if (m_settingsManager) {
        connect(m_settingsManager, &SettingsManager::wallpaperPathChanged, this, [this]() {
            if (!m_settingsManager) {
                return;
            }
            const QString newPath = m_settingsManager->wallpaperPath();
            if (!newPath.isEmpty() && newPath != m_currentWallpaper) {
                setCurrentWallpaper(newPath);
            }
        });
    }
}

void WallpaperStore::setWallpaper(const QString &newPath, bool newIsDark) {
    if (newPath.isEmpty()) {
        if (newIsDark != m_isDark) {
            setIsDark(newIsDark);
        }
        return;
    }
    if (newPath == m_currentWallpaper) {
        if (newIsDark != m_isDark) {
            setIsDark(newIsDark);
        }
        return;
    }
    setCurrentWallpaper(newPath);
    if (newIsDark != m_isDark) {
        setIsDark(newIsDark);
    }
    if (m_settingsManager && m_settingsManager->wallpaperPath() != newPath) {
        m_settingsManager->setWallpaperPath(newPath);
    }
}

QString WallpaperStore::resolveAssetPath(const QString &relativePath,
                                         const QString &fallback) const {
    if (m_settingsManager) {
        const QString assetUrl = m_settingsManager->assetUrl(relativePath);
        if (!assetUrl.isEmpty()) {
            return assetUrl;
        }
    }
    return fallback;
}

void WallpaperStore::setCurrentWallpaper(const QString &path) {
    if (m_currentWallpaper == path) {
        return;
    }
    m_currentWallpaper = path;
    emit currentWallpaperChanged();
    emit pathChanged();
    refreshIsDark();
}

void WallpaperStore::setIsDark(bool isDark) {
    if (m_isDark == isDark) {
        return;
    }
    m_isDark = isDark;
    emit isDarkChanged();
}

void WallpaperStore::refreshIsDark() {
    for (const QVariant &entry : m_wallpapers) {
        const QVariantMap map = entry.toMap();
        if (map.value("path").toString() == m_currentWallpaper) {
            setIsDark(map.value("isDark").toBool());
            return;
        }
    }
}
