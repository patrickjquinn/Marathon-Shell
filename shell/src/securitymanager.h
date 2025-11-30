#ifndef SECURITYMANAGER_H
#define SECURITYMANAGER_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <QDateTime>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QFuture>
#include <QFutureWatcher>
#include <security/pam_appl.h>

class SecurityManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(AuthMode authMode READ authMode WRITE setAuthMode NOTIFY authModeChanged)
    Q_PROPERTY(bool hasQuickPIN READ hasQuickPIN NOTIFY quickPINChanged)
    Q_PROPERTY(
        bool fingerprintAvailable READ fingerprintAvailable NOTIFY fingerprintAvailableChanged)
    Q_PROPERTY(bool isLockedOut READ isLockedOut NOTIFY lockoutStateChanged)
    Q_PROPERTY(int lockoutSecondsRemaining READ lockoutSecondsRemaining NOTIFY lockoutStateChanged)
    Q_PROPERTY(int failedAttempts READ failedAttempts NOTIFY failedAttemptsChanged)

  public:
    explicit SecurityManager(QObject *parent = nullptr);
    ~SecurityManager();

    enum AuthMode {
        SystemPassword, // PAM authentication with system password
        QuickPIN,       // Optional quick PIN stored in libsecret
        Biometric,      // Fingerprint only
        BiometricPIN    // Fingerprint with PIN fallback
    };
    Q_ENUM(AuthMode)

    enum BiometricType {
        Fingerprint,
        FaceRecognition
    };
    Q_ENUM(BiometricType)

    // Property getters
    AuthMode authMode() const {
        return m_authMode;
    }
    bool hasQuickPIN() const {
        return m_hasQuickPIN;
    }
    bool fingerprintAvailable() const {
        return m_fingerprintAvailable;
    }
    bool isLockedOut() const {
        return m_isLockedOut;
    }
    int lockoutSecondsRemaining() const;
    int failedAttempts() const {
        return m_failedAttempts;
    }

    // Property setters
    void setAuthMode(AuthMode mode);

    // Authentication methods
    Q_INVOKABLE void authenticatePassword(const QString &password);
    Q_INVOKABLE void authenticateQuickPIN(const QString &pin);
    Q_INVOKABLE void authenticateBiometric(BiometricType type = Fingerprint);
    Q_INVOKABLE void cancelAuthentication();

    // Quick PIN management (requires system password to set/change)
    Q_INVOKABLE void setQuickPIN(const QString &pin, const QString &systemPassword);
    Q_INVOKABLE void removeQuickPIN(const QString &systemPassword);

    // Biometric enrollment check
    Q_INVOKABLE bool isBiometricEnrolled(BiometricType type) const;

    // Lockout management
    Q_INVOKABLE void resetLockout(); // Admin/recovery function

    // Utility methods
    Q_INVOKABLE QString getCurrentUsername() const;

  signals:
    void authenticationSuccess();
    void authenticationFailed(const QString &reason);
    void authModeChanged();
    void quickPINChanged();
    void fingerprintAvailableChanged();
    void lockoutStateChanged();
    void failedAttemptsChanged();
    void biometricPrompt(const QString &message); // "Place your finger", etc.

  private slots:
    void onFingerprintVerifyStatus(const QString &result, bool done);
    void checkLockoutTimer();
    void onPasswordAuthFinished();
    void onQuickPINAuthFinished();

  private:
    // PAM authentication backend
    bool       authenticateViaPAM(const QString &password);
    static int pamConversationCallback(int num_msg, const struct pam_message **msg,
                                       struct pam_response **resp, void *appdata_ptr);

    // Quick PIN (encrypted in libsecret)
    bool    verifyQuickPIN(const QString &pin);
    bool    storeQuickPIN(const QString &pin);
    QString retrieveQuickPIN();
    void    clearQuickPIN();

    // fprintd D-Bus integration
    void initFingerprintDevice();
    void startFingerprintAuth();
    void stopFingerprintAuth();
    void checkFingerprintEnrollment();

    // Rate limiting and lockout (query pam_faillock)
    void updateLockoutStatus();
    void recordFailedAttempt();
    void resetFailedAttempts();
    int  queryFaillockAttempts();

    // Members
    AuthMode  m_authMode;
    bool      m_hasQuickPIN;
    bool      m_fingerprintAvailable;
    bool      m_isLockedOut;
    int       m_failedAttempts;
    QDateTime m_lockoutUntil;
    QTimer   *m_lockoutTimer;

    // fprintd D-Bus
    QDBusInterface *m_fprintdManager;
    QDBusInterface *m_fprintdDevice;
    bool            m_fprintdAuthInProgress;

    // PAM conversation data
    QString m_currentPassword;

    // Async authentication watchers
    QFutureWatcher<bool> *m_passwordAuthWatcher;
    QFutureWatcher<bool> *m_quickPINAuthWatcher;
};

#endif // SECURITYMANAGER_H
