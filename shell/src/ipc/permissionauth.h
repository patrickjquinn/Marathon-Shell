#pragma once

#include <QRegularExpression>
#include <QString>
#include <QVariantMap>

// Who may act on an app's permissions over Permissions1. caller is the
// shell-resolved app id of the D-Bus sender, never an argument.
namespace PermissionAuth {

    enum class Op : quint8 {
        Read,
        Request,
        Grant,
        Revoke,
    };

    inline bool isPermissionAdmin(const QString &caller) {
        return caller == QLatin1String("settings");
    }

    inline bool allowed(const QString &caller, const QString &targetAppId, Op op) {
        if (caller.isEmpty() || targetAppId.isEmpty())
            return false;
        if (isPermissionAdmin(caller))
            return caller == targetAppId || op != Op::Request;
        return caller == targetAppId && op != Op::Grant;
    }

    // The session-service permission (ServiceCaller) for prompting for apps
    // whose grants another system keeps: deckardd, for Android apps.
    inline const QString kForeignPrompts = QStringLiteral("android-permissions");

    // "waydroid.<Android package>".
    inline bool isAndroidAppId(const QString &appId) {
        static const QRegularExpression pkg(
            QStringLiteral("^waydroid\\.[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$"));
        return appId.size() <= 9 + 255 && pkg.match(appId).hasMatch();
    }

    // A foreign prompt's options, keeping only known keys with valid values.
    inline bool foreignOptions(const QVariantMap &in, QVariantMap *out) {
        const QString kind =
            in.value(QStringLiteral("kind"), QStringLiteral("foreground")).toString();
        const QString accuracy = in.value(QStringLiteral("accuracy")).toString();
        if (kind != QLatin1String("foreground") && kind != QLatin1String("background") &&
            kind != QLatin1String("precise"))
            return false;
        if (!accuracy.isEmpty() && accuracy != QLatin1String("choice") &&
            accuracy != QLatin1String("approximate"))
            return false;
        for (const char *flag : {"once", "preciseDefault"}) {
            const QVariant v = in.value(QLatin1String(flag));
            if (v.isValid() && v.metaType().id() != QMetaType::Bool)
                return false;
        }
        *out = {{QStringLiteral("kind"), kind},
                {QStringLiteral("once"), in.value(QStringLiteral("once")).toBool()},
                {QStringLiteral("accuracy"), accuracy},
                {QStringLiteral("preciseDefault"),
                 in.value(QStringLiteral("preciseDefault")).toBool()}};
        return true;
    }

} // namespace PermissionAuth
