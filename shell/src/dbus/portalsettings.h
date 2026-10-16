#pragma once

#include <QColor>
#include <QDBusArgument>
#include <QDBusContext>
#include <QDBusVariant>
#include <QMap>
#include <QObject>
#include <QStringList>
#include <QVariantMap>

using PortalNamespaces = QMap<QString, QVariantMap>;

// xdg-desktop-portal's Settings backend: the ambience in the namespaces each
// toolkit reads inside a Flatpak, org.freedesktop.appearance, GTK's
// org.gnome.desktop.interface and KDE's org.kde.kdeglobals.*.
class PortalSettings : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Settings")
    Q_PROPERTY(uint version READ version CONSTANT)

  public:
    explicit PortalSettings(QObject *parent = nullptr);

    // color-scheme (0 no preference, 1 dark, 2 light) and accent-color.
    static QVariantMap appearance(const QVariantMap &ambience);
    // Every namespace served for an ambience. gtk3Theme: whether GTK 3 can
    // load the Marathon themes, else it is pointed at Adwaita.
    static PortalNamespaces settings(const QVariantMap &ambience, bool gtk3Theme);
    // Whether a namespace matches ReadAll's filters ("" or "prefix.*" globs).
    static bool matches(const QString &ns, const QStringList &filters);

    uint        version() const {
        return 2;
    }

    void setGtk3Theme(bool installed);
    void setAmbience(const QVariantMap &ambience);

  public slots:
    PortalNamespaces ReadAll(const QStringList &namespaces);
    QDBusVariant     ReadOne(const QString &ns, const QString &key);
    QDBusVariant     Read(const QString &ns, const QString &key);

  signals:
    void SettingChanged(const QString &ns, const QString &key, const QDBusVariant &value);

  private:
    PortalNamespaces m_settings;
    bool             m_gtk3Theme = false;
};

Q_DECLARE_METATYPE(PortalNamespaces)
