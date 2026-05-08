#ifndef SECURITYLOGGER_H
#define SECURITYLOGGER_H

#include <QString>
#include <QDateTime>
#include <QMutex>
#include <syslog.h>

class SecurityLogger {
  public:
    enum EventType {
        AuthSuccess,
        AuthFailure,
        AuthLockout,
        PermissionGranted,
        PermissionDenied,
        PermissionRequested,
        SandboxViolation,
        RateLimitExceeded,
        PathTraversalBlocked,
        InvalidInput,
        EmergencyDial
    };

    static void initialize(const QString &appName = "marathon-shell") {
        static bool initialized = false;
        if (!initialized) {
            openlog(appName.toUtf8().constData(), LOG_PID | LOG_NDELAY, LOG_AUTH);
            initialized = true;
        }
    }

    static void logAuthSuccess(const QString &username, const QString &method) {
        log(AuthSuccess,
            QString("Authentication success: user=%1 method=%2").arg(username, method));
    }

    static void logAuthFailure(const QString &username, const QString &reason,
                               const QString &source = QString()) {
        QString msg = QString("Authentication failure: user=%1 reason=%2").arg(username, reason);
        if (!source.isEmpty()) {
            msg += QString(" source=%1").arg(source);
        }
        log(AuthFailure, msg);
    }

    static void logAuthLockout(const QString &username, int durationSeconds) {
        log(AuthLockout,
            QString("Account locked out: user=%1 duration=%2s").arg(username).arg(durationSeconds));
    }

    static void logPermissionGranted(const QString &appId, const QString &permission) {
        log(PermissionGranted,
            QString("Permission granted: app=%1 permission=%2").arg(appId, permission));
    }

    static void logPermissionDenied(const QString &appId, const QString &permission) {
        log(PermissionDenied,
            QString("Permission denied: app=%1 permission=%2").arg(appId, permission));
    }

    static void logPermissionRequested(const QString &appId, const QString &permission) {
        log(PermissionRequested,
            QString("Permission requested: app=%1 permission=%2").arg(appId, permission));
    }

    static void logSandboxViolation(const QString &appId, const QString &attemptedPath) {
        log(SandboxViolation,
            QString("Sandbox violation: app=%1 path=%2").arg(appId, attemptedPath));
    }

    static void logRateLimitExceeded(const QString &callerId, const QString &method,
                                     int callsPerSecond) {
        log(RateLimitExceeded,
            QString("Rate limit exceeded: caller=%1 method=%2 rate=%3/s")
                .arg(callerId, method)
                .arg(callsPerSecond));
    }

    static void logPathTraversalBlocked(const QString &source, const QString &maliciousPath) {
        log(PathTraversalBlocked,
            QString("Path traversal blocked: source=%1 path=%2").arg(source, maliciousPath));
    }

    static void logInvalidInput(const QString &source, const QString &field,
                                const QString &reason) {
        log(InvalidInput,
            QString("Invalid input rejected: source=%1 field=%2 reason=%3")
                .arg(source, field, reason));
    }

    // Audit trail for emergency dials. Logs metadata only -- never call
    // content / DTMF / audio. The dialed number is kept (it is, by design,
    // an emergency number -- these are public). Operator + emergencyOnly +
    // gpsAvailable help debug field reports without dragging in coordinates.
    static void logEmergencyDial(const QString &number, const QString &modemPath,
                                 const QString &networkOperator, bool emergencyOnly,
                                 bool gpsAvailable) {
        log(EmergencyDial,
            QString("Emergency dial: number=%1 modem=%2 operator=%3 emergencyOnly=%4 gps=%5")
                .arg(number, modemPath, networkOperator, emergencyOnly ? "yes" : "no",
                     gpsAvailable ? "yes" : "no"));
    }

  private:
    static void log(EventType type, const QString &message) {
        QString fullMessage = QString("[SECURITY] %1").arg(message);

        // Choose the Qt log channel that matches the event severity, so callers
        // tailing the shell log see the right colour/level. Syslog priority is
        // selected separately below so syslog stays informative regardless.
        int priority = LOG_AUTH;
        switch (type) {
            case AuthSuccess:
            case PermissionGranted:
                qInfo().noquote() << fullMessage;
                priority |= LOG_INFO;
                break;
            case EmergencyDial:
                // qWarning so it always lands in the journal, even when info
                // is suppressed for the default category. Emergency-call audit
                // visibility matters more than log-level cleanliness here.
                qWarning().noquote() << fullMessage;
                priority |= LOG_NOTICE;
                break;
            case AuthFailure:
            case PermissionDenied:
            case PermissionRequested:
                qWarning().noquote() << fullMessage;
                priority |= LOG_WARNING;
                break;
            case AuthLockout:
            case SandboxViolation:
            case RateLimitExceeded:
            case PathTraversalBlocked:
            case InvalidInput:
                qCritical().noquote() << fullMessage;
                priority |= LOG_ALERT;
                break;
        }

        syslog(priority, "%s", fullMessage.toUtf8().constData());
    }
};

#endif
