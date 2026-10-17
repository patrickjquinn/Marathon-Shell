#include "marathonmanifest.h"
#include "marathon-core-native/src/lib.rs.h"

static QString fromRust(const rust::String &s) {
    return QString::fromUtf8(s.data(), static_cast<qsizetype>(s.size()));
}

QList<MarathonManifest::Finding> MarathonManifest::lint(const QString &path, bool systemApp) {
    const QByteArray utf8 = path.toUtf8();
    QList<Finding>   findings;
    for (const marathon::native::LintFinding &f :
         marathon::native::lint_app(rust::Str(utf8.constData(), utf8.size()), systemApp))
        findings.append({f.error, fromRust(f.rule), fromRust(f.path), fromRust(f.message)});
    return findings;
}

QList<MarathonManifest::Permission> MarathonManifest::permissions() {
    QList<Permission> permissions;
    for (const marathon::native::PermissionInfo &p : marathon::native::permission_vocabulary())
        permissions.append({fromRust(p.name), fromRust(p.label), fromRust(p.description),
                            p.sensitive, p.restricted});
    return permissions;
}

QString MarathonManifest::canonicalPermission(const QString &name) {
    const QByteArray utf8 = name.toUtf8();
    return fromRust(
        marathon::native::canonical_permission(rust::Str(utf8.constData(), utf8.size())));
}
