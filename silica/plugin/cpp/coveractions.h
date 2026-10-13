// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// A cover's actions as Lipstick takes them in direct mode. Lipstick draws
// the action icons over the cover itself and does not pass taps on them to
// the cover window: it learns the actions from the property
// _APP_COVER_ACTION on the app's window (not the cover's) and calls the app
// back over D-Bus when one is tapped.
// What Silica's Qt 5 CoverActionList does, as observed on a Jolla Phone
// (Sailfish OS 5.2.0.18, lipstick-jolla-home-qt5 1.27.18; Silica's and
// Lipstick's code is closed):
//
// * The app owns the session bus name
//   org.sailfishos.coveraction.<organization>.<application>.pid<pid>.id<n>
//   (Base.permission lets every Sailjail app own org.sailfishos.coveraction.*)
//   and serves, at that name with '.' turned into '/', the interface
//   org.sailfishos.silica.coveraction with the method trigger(int index).
// * The app window's _APP_COVER_ACTION is one string, its fields joined
//   by '\n': for each action <service>, "trigger", <index>, <icon source>,
//   then "1" or "0" for CoverActionList.iconBackground.
// * Silica refuses trigger() from anyone but the owner of com.jolla.lipstick.
//
// Thin C++ like the rest of the shell client: D-Bus plumbing only.
#ifndef KEEL_COVERACTIONS_H
#define KEEL_COVERACTIONS_H

#include <QDBusConnection>
#include <QDBusContext>
#include <QObject>
#include <QString>
#include <QStringList>

namespace keel {

class CoverActions : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sailfishos.silica.coveraction")

public:
    // Owns `service` on `bus` and serves the object for it. registered()
    // says whether both worked.
    CoverActions(const QDBusConnection &bus, const QString &service, QObject *parent = nullptr);
    ~CoverActions() override;

    bool registered() const { return m_registered; }
    QString service() const { return m_service; }

    // The bus name for one cover window: every element made a valid D-Bus
    // name element (and so a valid object path element).
    static QString serviceName(const QString &organization, const QString &application,
                               qint64 pid, uint windowId);
    // The object path Lipstick calls: the name with '.' turned into '/'.
    static QString objectPath(const QString &service);
    // The _APP_COVER_ACTION value; empty for no actions.
    static QString propertyValue(const QString &service, const QStringList &icons, bool iconBackground);

public slots:
    // Called by Lipstick when the action at `index` is tapped.
    Q_SCRIPTABLE void trigger(int index);

signals:
    void triggered(int index);

private:
    QDBusConnection m_bus;
    QString m_service;
    QString m_path;
    bool m_registered = false;
};

} // namespace keel

#endif // KEEL_COVERACTIONS_H
