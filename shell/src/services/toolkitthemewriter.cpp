#include "toolkitthemewriter.h"
#include "toolkittheme.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

namespace {
    void replace(const QString &path, const QString &content) {
        if (!ToolkitThemeWriter::ours(path))
            return;
        const QByteArray bytes = content.toUtf8();
        {
            QFile current(path);
            if (current.open(QIODevice::ReadOnly) && current.readAll() == bytes)
                return;
        }
        QDir().mkpath(QFileInfo(path).absolutePath());
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
            qWarning() << "[ToolkitThemeWriter] Could not write" << path << file.errorString();
    }
} // namespace

ToolkitThemeWriter::ToolkitThemeWriter(const QString &configHome, const QString &dataHome)
    : m_gtk4Css(configHome + QStringLiteral("/gtk-4.0/gtk.css"))
    , m_gtk3Light(dataHome + QStringLiteral("/themes/Marathon/gtk-3.0/gtk.css"))
    , m_gtk3Dark(dataHome + QStringLiteral("/themes/Marathon-dark/gtk-3.0/gtk.css")) {}

bool ToolkitThemeWriter::ours(const QString &path) {
    QFile file(path);
    if (!file.exists())
        return true;
    return file.open(QIODevice::ReadOnly) &&
        file.readLine().trimmed() == QByteArray(ToolkitTheme::kMarker);
}

void ToolkitThemeWriter::write(const QColor &highlight, bool dark) const {
    replace(m_gtk4Css, ToolkitTheme::gtk4Css(highlight, dark));
    replace(m_gtk3Light, ToolkitTheme::gtk3Css(ToolkitTheme::palette(highlight, false)));
    replace(m_gtk3Dark, ToolkitTheme::gtk3Css(ToolkitTheme::palette(highlight, true)));
}

bool ToolkitThemeWriter::gtk3ThemeInstalled() const {
    return QFileInfo::exists(m_gtk3Light) && QFileInfo::exists(m_gtk3Dark);
}
