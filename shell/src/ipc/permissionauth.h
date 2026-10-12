#pragma once

#include <QString>

// Who may act on an app's permissions over Permissions1. caller is the
// shell-resolved app id of the D-Bus sender, never an argument.
namespace PermissionAuth {

    enum class Op {
        Read,
        Request,
        Change,
    };

    inline bool isPermissionAdmin(const QString &caller) {
        return caller == QLatin1String("settings");
    }

    inline bool allowed(const QString &caller, const QString &targetAppId, Op op) {
        if (caller.isEmpty() || targetAppId.isEmpty())
            return false;
        if (caller == targetAppId)
            return true;
        return op != Op::Request && isPermissionAdmin(caller);
    }

} // namespace PermissionAuth
