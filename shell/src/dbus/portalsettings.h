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

// xdg-desktop-portal's Settings backend for the appearance namespace:
// color-scheme and accent-color from the shell's ambience, so GTK, Qt and
// web content follow the wallpaper as Keel apps do.
class PortalSettings : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Settings")
    Q_PROPERTY(uint version READ version CONSTANT)

  public:
    explicit PortalSettings(QObject *parent = nullptr);

    // color-scheme (0 no preference, 1 dark, 2 light) and accent-color.
    static QVariantMap appearance(const QVariantMap &ambience);
    // Whether a namespace matches ReadAll's filters ("" or "prefix.*" globs).
    static bool matches(const QString &ns, const QStringList &filters);

    uint version() const {
        return 2;
    }

    void setAmbience(const QVariantMap &ambience);

  public slots:
    PortalNamespaces ReadAll(const QStringList &namespaces);
    QDBusVariant     ReadOne(const QString &ns, const QString &key);
    QDBusVariant     Read(const QString &ns, const QString &key);

  signals:
    void SettingChanged(const QString &ns, const QString &key, const QDBusVariant &value);

  private:
    QVariant dbusValue(const QString &key) const;

    QVariantMap m_appearance;
};

Q_DECLARE_METATYPE(PortalNamespaces)
