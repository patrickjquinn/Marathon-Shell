#pragma once

#include <QColor>
#include <QString>

// Writes the ambience's GTK styling where GTK reads it: libadwaita's colours
// to $XDG_CONFIG_HOME/gtk-4.0/gtk.css and the GTK 3 "Marathon" themes to
// $XDG_DATA_HOME/themes. Flatpak apps see both through the system override.
class ToolkitThemeWriter {
  public:
    ToolkitThemeWriter(const QString &configHome, const QString &dataHome);

    void write(const QColor &highlight, bool dark) const;
    // Whether GTK 3 apps can load "Marathon" and "Marathon-dark".
    bool gtk3ThemeInstalled() const;
    // A file Marathon may replace: absent, or one it generated.
    static bool ours(const QString &path);

  private:
    QString m_gtk4Css;
    QString m_gtk3Light;
    QString m_gtk3Dark;
};
