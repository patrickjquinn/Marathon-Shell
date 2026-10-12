#pragma once

#include <QDBusMessage>
#include <QDataStream>
#include <QStringList>

// Nemo.Notifications' remote actions: a hint "x-nemo-remote-action-<name>"
// holding "<service> <path> <interface> <method> <base64 QDataStream arg>...",
// the D-Bus call to make when that action (or "default", a tap) is invoked.
namespace NemoRemoteAction {

inline QString hintName(const QString &action) {
    return QStringLiteral("x-nemo-remote-action-") + action;
}

inline QDBusMessage decode(const QString &hint, bool *ok) {
    const QStringList parts = hint.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    *ok                     = parts.size() >= 4;
    if (!*ok)
        return {};
    QDBusMessage call = QDBusMessage::createMethodCall(parts.at(0), parts.at(1), parts.at(2), parts.at(3));
    QVariantList args;
    for (int i = 4; i < parts.size(); ++i) {
        QDataStream stream(QByteArray::fromBase64(parts.at(i).toLatin1()));
        QVariant    arg;
        stream >> arg;
        args << arg;
    }
    call.setArguments(args);
    return call;
}

} // namespace NemoRemoteAction
