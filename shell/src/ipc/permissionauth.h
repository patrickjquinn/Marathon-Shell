#pragma once

#include <QString>

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

} // namespace PermissionAuth
