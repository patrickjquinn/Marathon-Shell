#pragma once

#include <QString>
#include <QVariantMap>

// Sailfish apps (an [X-Sailjail] group, or sailfish-qml) run under
// marathon-keel-host, which gives them the Keel host Silica expects.
namespace SailfishLaunch {

inline QString command(const QVariantMap &app, const QString &exec) {
    if (!app.value(QStringLiteral("sailfish")).toBool())
        return exec;
    return QStringLiteral("marathon-keel-host --app-id %1 -- %2")
        .arg(app.value(QStringLiteral("id")).toString(), exec);
}

} // namespace SailfishLaunch
