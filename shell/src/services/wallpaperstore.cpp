#include "wallpaperstore.h"
#include "src/managers/settingsmanager.h"
#include <QVariant>
#include <QVariantMap>

WallpaperStore::WallpaperStore(SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , m_settingsManager(settingsManager) {
    m_wallpapers = {// DS 2026 — Slate Aurora ships as the only default for now. The
                    // legacy `wallpaper.jpg…wallpaper8.jpg` stock photos have been
                    // removed; they were inherited from the pre-DS scaffold and don't
                    // match the design system. The remaining 12 wallpapers from
                    // docs/redesign/marathonos/project/wallpapers.jsx (Carbon,
                    // IndigoDusk, LongRun, Flowfield, Mesh, Topographic, Drift,
                    // Tundra, Striae, Halftone, Pulse, Twilight) are queued to be
                    // rendered to SVG and shipped alongside slate-aurora.svg.
                    QVariantMap{{"name", "Slate Aurora"},
                                {"path",
                                 resolveAssetPath("wallpapers/slate-aurora.svg",
                                                  "qrc:/wallpapers/slate-aurora.svg")},
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
