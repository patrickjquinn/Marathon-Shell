#ifndef SECURITYAUDIT_H
#define SECURITYAUDIT_H

#include <QString>

#include "securitylogger.h"

// The authentication audit lines for the Rust security service
// (crates/marathon-shell-native/src/security.rs), through SecurityLogger so
// they stay in syslog's auth facility.
namespace marathon::audit {

    inline void authSuccess(const QString &user, const QString &method) {
        SecurityLogger::initialize();
        SecurityLogger::logAuthSuccess(user, method);
    }

    inline void authFailure(const QString &user, const QString &reason, const QString &source) {
        SecurityLogger::initialize();
        SecurityLogger::logAuthFailure(user, reason, source);
    }

    inline void authLockout(const QString &user, int seconds) {
        SecurityLogger::initialize();
        SecurityLogger::logAuthLockout(user, seconds);
    }

} // namespace marathon::audit

#endif
