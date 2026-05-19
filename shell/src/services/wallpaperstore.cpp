#include "wallpaperstore.h"
#include "src/managers/settingsmanager.h"
#include <QVariant>
#include <QVariantMap>

WallpaperStore::WallpaperStore(SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , m_settingsManager(settingsManager) {
    // All 13 DS 2026 wallpapers from docs/redesign/marathonos/project/wallpapers.jsx,
    // rendered to static SVG via scripts/build-wallpapers.py. Slate Aurora is the
    // boot default. Order matches the design canvas (signature mark first, then
    // structural pieces, then the gradient / atmospheric set, then dawn).
    auto wp = [this](const char *name, const char *file, bool dark) -> QVariantMap {
        const QString rel = QStringLiteral("wallpapers/") + QLatin1String(file);
        const QString qrc = QStringLiteral("qrc:/wallpapers/") + QLatin1String(file);
        return QVariantMap{
            {"name", QLatin1String(name)},
            {"path", resolveAssetPath(rel, qrc)},
            {"isDark", dark},
        };
    };
    m_wallpapers = {
        wp("Slate Aurora", "slate-aurora.svg", true),
        wp("Long Run", "long-run.svg", true),
        wp("Carbon", "carbon.svg", true),
        wp("Indigo Dusk", "indigo-dusk.svg", true),
        wp("Track", "track.svg", true),
        wp("Mesh", "mesh.svg", true),
        wp("Contour", "contour.svg", true),
        wp("Stride", "stride.svg", true),
        wp("Tundra", "tundra.svg", true),
        wp("Striae", "striae.svg", true),
        wp("Halftone", "halftone.svg", true),
        wp("Pulse", "pulse.svg", true),
        wp("Dawn", "dawn.svg", true),
    };
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
