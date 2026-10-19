#ifndef CALLERPID_H
#define CALLERPID_H

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <string>

#include "marathon-shell-native/src/identity.cxxqt.h"

// The PID behind a D-Bus name, -1 if unknown. Session-bus names come from
// the cache crates/marathon-shell-native/src/identity.rs fills on the I/O
// thread as connections appear; only a name not seen yet asks the daemon.
inline qint64 callerPid(const QDBusConnection &bus, const QString &name) {
    const bool        session = bus.name() == QDBusConnection::sessionBus().name();
    const std::string key     = name.toStdString();
    if (session) {
        if (const qint64 pid = marathon::identity::pid_of(key); pid >= 0)
            return pid;
    }
    if (!bus.interface())
        return -1;
    const QDBusReply<uint> reply = bus.interface()->servicePid(name);
    if (!reply.isValid())
        return -1;
    if (session)
        marathon::identity::remember(key, reply.value());
    return reply.value();
}

#endif
