// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See sailfishaccesscontrol.h: whether a user belongs to a group, primary or
// supplementary, from the system's user and group databases.

#include "sailfishaccesscontrol.h"

#include <grp.h>
#include <pwd.h>

#include <vector>

bool sailfish_access_control_hasgroup(uid_t uid, const char *group_name)
{
    if (!group_name)
        return false;
    const struct group *group = getgrnam(group_name);
    const struct passwd *user = getpwuid(uid);
    if (!group || !user)
        return false;
    const gid_t wanted = group->gr_gid;
    if (user->pw_gid == wanted)
        return true;
    int count = 32;
    std::vector<gid_t> groups(static_cast<size_t>(count));
    if (getgrouplist(user->pw_name, user->pw_gid, groups.data(), &count) < 0) {
        groups.resize(static_cast<size_t>(count));
        if (getgrouplist(user->pw_name, user->pw_gid, groups.data(), &count) < 0)
            return false;
    }
    for (int i = 0; i < count; ++i) {
        if (groups[static_cast<size_t>(i)] == wanted)
            return true;
    }
    return false;
}
