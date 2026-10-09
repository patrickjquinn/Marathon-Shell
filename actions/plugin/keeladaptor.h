// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// org.shipwright.Keel.Actions on the session bus (keel/actions/dbus), at
// /org/shipwright/Keel/Actions on the app's ID. Calls are answered
// asynchronously (delayed replies) when the action answers. In headless
// mode (D-Bus activation, --keel-actions) the app quits after
// KEEL_ACTIONS_IDLE_MS (default 30,000) without calls.
#ifndef KEEL_ACTIONS_ADAPTOR_H
#define KEEL_ACTIONS_ADAPTOR_H

#include <QDBusMessage>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

class KeelActionRegistry;
class KeelCall;

class KeelActionsAdaptor : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.Keel.Actions")

public:
    static constexpr const char *Path = "/org/shipwright/Keel/Actions";
    static constexpr int DefaultIdleMs = 30000;

    explicit KeelActionsAdaptor(KeelActionRegistry *registry);

    // Registers the object and requests the app ID on the session bus.
    bool start();

public Q_SLOTS:
    QString Describe();
    QString Invoke(const QString &action, const QString &arguments, const QVariantMap &options,
                   const QDBusMessage &message);
    QString GetEntity(const QString &type, const QString &id, const QDBusMessage &message);
    QString FindEntities(const QString &type, const QString &query, uint limit, const QDBusMessage &message);
    QString GetContext();

private:
    void answer(KeelCall *call, const QDBusMessage &message);
    void touch();

    KeelActionRegistry *m_registry;
    QTimer m_idle;
    int m_inFlight = 0;
};

#endif
