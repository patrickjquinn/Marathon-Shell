#pragma once

#include <QList>
#include <QString>

// App manifest contract (docs/APP_MANIFEST_SCHEMA.md), implemented in
// crates/marathon-core-native/src/manifest.rs.
namespace MarathonManifest {

    struct Finding {
        bool    error = false;
        QString rule;
        QString path;
        QString message;
    };

    // Lints an app directory or .marathon package. systemApp admits
    // Marathon's own apps (single-word ids, protected, restricted permissions).
    QList<Finding> lint(const QString &path, bool systemApp);

    struct Permission {
        QString name;
        QString label;
        QString description;
        bool    sensitive  = false;
        bool    restricted = false;
    };

    // schemas/marathon-permissions-v1.json.
    QList<Permission> permissions();

    // The permission a name or alias ("phone") means; empty if none.
    QString canonicalPermission(const QString &name);

} // namespace MarathonManifest
