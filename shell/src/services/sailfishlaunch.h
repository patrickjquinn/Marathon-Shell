#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>

// Sailfish apps (an [X-Sailjail] group, or sailfish-qml) run under
// marathon-keel-host, which gives them the Keel host Silica expects and,
// when they declare Sailjail permissions, a sandbox built from them.
namespace SailfishLaunch {

inline QString command(const QVariantMap &app, const QString &exec) {
    if (!app.value(QStringLiteral("sailfish")).toBool())
        return exec;
    QString     host = QStringLiteral("marathon-keel-host --app-id ") + app.value(QStringLiteral("id")).toString();
    const QString org  = app.value(QStringLiteral("sailjailOrganization")).toString();
    const QString name = app.value(QStringLiteral("sailjailApplication")).toString();
    if (app.contains(QStringLiteral("sailjailPermissions")) && !org.isEmpty() && !name.isEmpty()) {
        host += QStringLiteral(" --sailjail ") +
                app.value(QStringLiteral("sailjailPermissions")).toStringList().join(QLatin1Char(',')) +
                QStringLiteral(" --org ") + org + QStringLiteral(" --app ") + name;
    }
    return host + QStringLiteral(" -- ") + exec;
}

} // namespace SailfishLaunch
