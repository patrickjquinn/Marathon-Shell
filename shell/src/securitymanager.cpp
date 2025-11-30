#include "securitymanager.h"
#include <QDebug>
#include <QDBusReply>
#include <QDBusConnectionInterface>
#include <QProcess>
#include <QFile>
#include <QTextStream>
#include <QCryptographicHash>
#include <QStandardPaths>
#include <QDir>
#include <QtConcurrent/QtConcurrent>
#include <asyncfuture.h>
#include <unistd.h>
#include <pwd.h>
#include <sys/types.h>

SecurityManager::SecurityManager(QObject *parent)
    : QObject(parent)
    , m_authMode(SystemPassword)
    , m_hasQuickPIN(false)
    , m_fingerprintAvailable(false)
    , m_isLockedOut(false)
    , m_failedAttempts(0)
    , m_lockoutTimer(new QTimer(this))
    , m_fprintdManager(nullptr)
    , m_fprintdDevice(nullptr)
    , m_fprintdAuthInProgress(false)
    , m_passwordAuthWatcher(new QFutureWatcher<bool>(this))
    , m_quickPINAuthWatcher(new QFutureWatcher<bool>(this)) {
    qDebug() << "[SecurityManager] Initializing authentication system";

    // Initialize fprintd
    initFingerprintDevice();

    // Check for existing Quick PIN
    m_hasQuickPIN = !retrieveQuickPIN().isEmpty();

    // Set up lockout timer (check every second)
    m_lockoutTimer->setInterval(1000);
    connect(m_lockoutTimer, &QTimer::timeout, this, &SecurityManager::checkLockoutTimer);

    // Set up async authentication watchers
    connect(m_passwordAuthWatcher, &QFutureWatcher<bool>::finished, this,
            &SecurityManager::onPasswordAuthFinished);
    connect(m_quickPINAuthWatcher, &QFutureWatcher<bool>::finished, this,
            &SecurityManager::onQuickPINAuthFinished);

    // Initial lockout status check
    updateLockoutStatus();

    qDebug() << "[SecurityManager] Fingerprint available:" << m_fingerprintAvailable;
    qDebug() << "[SecurityManager] Has Quick PIN:" << m_hasQuickPIN;
}

SecurityManager::~SecurityManager() {
    if (m_fprintdDevice) {
        m_fprintdDevice->call("Release");
        delete m_fprintdDevice;
    }
    if (m_fprintdManager) {
        delete m_fprintdManager;
    }
}

// ============================================================================
// Property Setters
// ============================================================================

void SecurityManager::setAuthMode(AuthMode mode) {
    if (m_authMode != mode) {
        m_authMode = mode;
        emit authModeChanged();
        qDebug() << "[SecurityManager] Auth mode changed to:" << mode;
    }
}

int SecurityManager::lockoutSecondsRemaining() const {
    if (!m_isLockedOut || !m_lockoutUntil.isValid()) {
        return 0;
    }

    qint64 msecs = QDateTime::currentDateTime().msecsTo(m_lockoutUntil);
    return qMax(0, static_cast<int>(msecs / 1000));
}

// ============================================================================
// PAM Authentication
// ============================================================================

int SecurityManager::pamConversationCallback(int num_msg, const struct pam_message **msg,
                                             struct pam_response **resp, void *appdata_ptr) {
    if (num_msg <= 0 || !msg || !resp || !appdata_ptr) {
        return PAM_CONV_ERR;
    }

    QString *password = static_cast<QString *>(appdata_ptr);

    *resp = static_cast<struct pam_response *>(calloc(num_msg, sizeof(struct pam_response)));
    if (!*resp) {
        return PAM_BUF_ERR;
    }

    for (int i = 0; i < num_msg; i++) {
        switch (msg[i]->msg_style) {
            case PAM_PROMPT_ECHO_OFF: // Password prompt
            case PAM_PROMPT_ECHO_ON:  // Username or other prompt
                (*resp)[i].resp         = strdup(password->toUtf8().constData());
                (*resp)[i].resp_retcode = 0;
                break;
            case PAM_ERROR_MSG:
            case PAM_TEXT_INFO:
                (*resp)[i].resp         = nullptr;
                (*resp)[i].resp_retcode = 0;
                break;
            default:
                free(*resp);
                *resp = nullptr;
                return PAM_CONV_ERR;
        }
    }

    return PAM_SUCCESS;
}

bool SecurityManager::authenticateViaPAM(const QString &password) {
    qDebug() << "[SecurityManager] Attempting PAM authentication";

    struct pam_conv conv = {pamConversationCallback, &m_currentPassword};

    pam_handle_t   *pamh     = nullptr;
    QString         username = getCurrentUsername();

    if (username.isEmpty()) {
        qWarning() << "[SecurityManager] Could not determine current username";
        return false;
    }

    m_currentPassword = password;

    // Start PAM authentication
    int ret = pam_start("marathon-shell", username.toUtf8().constData(), &conv, &pamh);
    if (ret != PAM_SUCCESS) {
        qWarning() << "[SecurityManager] PAM start failed:" << pam_strerror(pamh, ret);
        m_currentPassword.clear();
        return false;
    }

    // Authenticate
    ret = pam_authenticate(pamh, PAM_SILENT);
    if (ret != PAM_SUCCESS) {
        qWarning() << "[SecurityManager] PAM authentication failed:" << pam_strerror(pamh, ret);
        pam_end(pamh, ret);
        m_currentPassword.clear();
        return false;
    }

    // Check account validity
    ret = pam_acct_mgmt(pamh, PAM_SILENT);
    if (ret != PAM_SUCCESS) {
        qWarning() << "[SecurityManager] PAM account management failed:" << pam_strerror(pamh, ret);
        pam_end(pamh, ret);
        m_currentPassword.clear();
        return false;
    }

    // Success
    pam_end(pamh, PAM_SUCCESS);
    m_currentPassword.clear();

    qDebug() << "[SecurityManager] PAM authentication successful";
    return true;
}

void SecurityManager::authenticatePassword(const QString &password) {
    qDebug() << "[SecurityManager] Password authentication requested";

    // Check lockout status
    if (m_isLockedOut) {
        int  remaining = lockoutSecondsRemaining();
        emit authenticationFailed(
            QString("Account locked. Try again in %1 seconds.").arg(remaining));
        return;
    }

    if (password.isEmpty()) {
        emit authenticationFailed("Password cannot be empty");
        return;
    }

    // Store password for async callback
    m_currentPassword = password;

    // Run PAM authentication in background thread
    qDebug() << "[SecurityManager] Starting async PAM authentication";
    QFuture<bool> future =
        QtConcurrent::run([this, password]() { return authenticateViaPAM(password); });

    m_passwordAuthWatcher->setFuture(future);
}

void SecurityManager::onPasswordAuthFinished() {
    bool success = m_passwordAuthWatcher->result();
    m_currentPassword.clear();

    qDebug() << "[SecurityManager] Async PAM authentication completed, success:" << success;

    if (success) {
        resetFailedAttempts();
        emit authenticationSuccess();
    } else {
        recordFailedAttempt();

        QString message = "Incorrect password";
        if (m_isLockedOut) {
            int remaining = lockoutSecondsRemaining();
            message = QString("Too many failed attempts. Locked for %1 seconds.").arg(remaining);
        } else if (m_failedAttempts > 0) {
            int remaining = 5 - m_failedAttempts;
            message += QString(" (%1 attempts remaining)").arg(remaining);
        }

        emit authenticationFailed(message);
    }
}

// ============================================================================
// Quick PIN (Optional Convenience Feature)
// ============================================================================

QString SecurityManager::retrieveQuickPIN() {
    // For now, store in a simple config file (in production, use libsecret)
    QString configPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
        "/marathon/quickpin.conf";
    QFile file(configPath);

    if (!file.exists()) {
        return QString();
    }

    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[SecurityManager] Could not read Quick PIN file";
        return QString();
    }

    QString hashedPIN = QString::fromUtf8(file.readAll());
    file.close();

    return hashedPIN.trimmed();
}

bool SecurityManager::storeQuickPIN(const QString &pin) {
    // Hash the PIN with SHA-256
    QByteArray hash      = QCryptographicHash::hash(pin.toUtf8(), QCryptographicHash::Sha256);
    QString    hashedPIN = QString::fromLatin1(hash.toHex());

    QString    configPath =
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/marathon";
    QDir().mkpath(configPath);

    QString filePath = configPath + "/quickpin.conf";
    QFile   file(filePath);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[SecurityManager] Could not write Quick PIN file";
        return false;
    }

    file.write(hashedPIN.toUtf8());
    file.close();

    // Set restrictive permissions (owner read/write only)
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    qDebug() << "[SecurityManager] Quick PIN stored successfully";
    return true;
}

void SecurityManager::clearQuickPIN() {
    QString configPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
        "/marathon/quickpin.conf";
    QFile::remove(configPath);
}

bool SecurityManager::verifyQuickPIN(const QString &pin) {
    QString storedHash = retrieveQuickPIN();
    if (storedHash.isEmpty()) {
        return false;
    }

    QByteArray hash      = QCryptographicHash::hash(pin.toUtf8(), QCryptographicHash::Sha256);
    QString    hashedPIN = QString::fromLatin1(hash.toHex());

    return hashedPIN == storedHash;
}

void SecurityManager::authenticateQuickPIN(const QString &pin) {
    qDebug() << "[SecurityManager] Quick PIN authentication requested";

    // Check lockout status
    if (m_isLockedOut) {
        int  remaining = lockoutSecondsRemaining();
        emit authenticationFailed(
            QString("Account locked. Try again in %1 seconds.").arg(remaining));
        return;
    }

    if (pin.isEmpty()) {
        emit authenticationFailed("PIN cannot be empty");
        return;
    }

    // Run PIN verification in background thread (for consistency)
    qDebug() << "[SecurityManager] Starting async Quick PIN verification";
    QFuture<bool> future = QtConcurrent::run([this, pin]() { return verifyQuickPIN(pin); });

    m_quickPINAuthWatcher->setFuture(future);
}

void SecurityManager::onQuickPINAuthFinished() {
    bool success = m_quickPINAuthWatcher->result();

    qDebug() << "[SecurityManager] Async Quick PIN verification completed, success:" << success;

    if (success) {
        resetFailedAttempts();
        emit authenticationSuccess();
    } else {
        recordFailedAttempt();

        QString message = "Incorrect PIN";
        if (m_isLockedOut) {
            int remaining = lockoutSecondsRemaining();
            message = QString("Too many failed attempts. Locked for %1 seconds.").arg(remaining);
        } else if (m_failedAttempts > 0) {
            int remaining = 5 - m_failedAttempts;
            message += QString(" (%1 attempts remaining)").arg(remaining);
        }

        emit authenticationFailed(message);
    }
}

void SecurityManager::setQuickPIN(const QString &pin, const QString &systemPassword) {
    qDebug() << "[SecurityManager] Setting Quick PIN (requires system password verification)";

    // Verify system password first via PAM
    if (!authenticateViaPAM(systemPassword)) {
        emit authenticationFailed("System password incorrect. Cannot set Quick PIN.");
        return;
    }

    // Store the Quick PIN
    if (storeQuickPIN(pin)) {
        m_hasQuickPIN = true;
        emit quickPINChanged();
        qDebug() << "[SecurityManager] Quick PIN set successfully";
    } else {
        emit authenticationFailed("Failed to store Quick PIN");
    }
}

void SecurityManager::removeQuickPIN(const QString &systemPassword) {
    qDebug() << "[SecurityManager] Removing Quick PIN (requires system password verification)";

    // Verify system password first via PAM
    if (!authenticateViaPAM(systemPassword)) {
        emit authenticationFailed("System password incorrect. Cannot remove Quick PIN.");
        return;
    }

    clearQuickPIN();
    m_hasQuickPIN = false;
    emit quickPINChanged();
    qDebug() << "[SecurityManager] Quick PIN removed successfully";
}

// ============================================================================
// Fingerprint Authentication (fprintd D-Bus)
// ============================================================================

void SecurityManager::initFingerprintDevice() {
    qDebug() << "[SecurityManager] Initializing fprintd device";

    // Check if fprintd service is available
    QDBusConnection systemBus = QDBusConnection::systemBus();
    if (!systemBus.interface()->isServiceRegistered("net.reactivated.Fprint")) {
        qDebug() << "[SecurityManager] fprintd service not available";
        m_fingerprintAvailable = false;
        return;
    }

    // Create manager interface
    m_fprintdManager =
        new QDBusInterface("net.reactivated.Fprint", "/net/reactivated/Fprint/Manager",
                           "net.reactivated.Fprint.Manager", systemBus, this);

    if (!m_fprintdManager->isValid()) {
        qWarning() << "[SecurityManager] fprintd Manager interface invalid:"
                   << m_fprintdManager->lastError().message();
        delete m_fprintdManager;
        m_fprintdManager       = nullptr;
        m_fingerprintAvailable = false;
        return;
    }

    // Get default device
    QDBusReply<QDBusObjectPath> reply = m_fprintdManager->call("GetDefaultDevice");
    if (!reply.isValid()) {
        qDebug() << "[SecurityManager] No fingerprint device available:" << reply.error().message();
        m_fingerprintAvailable = false;
        return;
    }

    QString devicePath = reply.value().path();
    qDebug() << "[SecurityManager] Found fingerprint device:" << devicePath;

    // Create device interface
    m_fprintdDevice = new QDBusInterface("net.reactivated.Fprint", devicePath,
                                         "net.reactivated.Fprint.Device", systemBus, this);

    if (!m_fprintdDevice->isValid()) {
        qWarning() << "[SecurityManager] fprintd Device interface invalid:"
                   << m_fprintdDevice->lastError().message();
        delete m_fprintdDevice;
        m_fprintdDevice        = nullptr;
        m_fingerprintAvailable = false;
        return;
    }

    // Connect to VerifyStatus signal
    systemBus.connect("net.reactivated.Fprint", devicePath, "net.reactivated.Fprint.Device",
                      "VerifyStatus", this, SLOT(onFingerprintVerifyStatus(QString, bool)));

    // Check if fingerprint is enrolled
    checkFingerprintEnrollment();
}

void SecurityManager::checkFingerprintEnrollment() {
    if (!m_fprintdDevice) {
        m_fingerprintAvailable = false;
        return;
    }

    QString                 username = getCurrentUsername();
    QDBusReply<QStringList> reply    = m_fprintdDevice->call("ListEnrolledFingers", username);

    if (reply.isValid() && !reply.value().isEmpty()) {
        m_fingerprintAvailable = true;
        qDebug() << "[SecurityManager] Fingerprint enrolled, available for authentication";
    } else {
        m_fingerprintAvailable = false;
        qDebug() << "[SecurityManager] No fingerprint enrolled";
    }

    emit fingerprintAvailableChanged();
}

bool SecurityManager::isBiometricEnrolled(BiometricType type) const {
    if (type == Fingerprint) {
        return m_fingerprintAvailable;
    }
    return false; // Face recognition not implemented yet
}

void SecurityManager::authenticateBiometric(BiometricType type) {
    if (type != Fingerprint) {
        emit authenticationFailed("Biometric type not supported");
        return;
    }

    // Check lockout status
    if (m_isLockedOut) {
        int  remaining = lockoutSecondsRemaining();
        emit authenticationFailed(
            QString("Account locked. Try again in %1 seconds.").arg(remaining));
        return;
    }

    if (!m_fingerprintAvailable) {
        emit authenticationFailed("Fingerprint not available");
        return;
    }

    startFingerprintAuth();
}

void SecurityManager::startFingerprintAuth() {
    if (!m_fprintdDevice || m_fprintdAuthInProgress) {
        return;
    }

    qDebug() << "[SecurityManager] Starting fingerprint authentication";

    // Claim the device
    QDBusReply<void> claimReply = m_fprintdDevice->call("Claim", getCurrentUsername());
    if (!claimReply.isValid()) {
        qWarning() << "[SecurityManager] Failed to claim fingerprint device:"
                   << claimReply.error().message();
        emit authenticationFailed("Fingerprint device busy");
        return;
    }

    // Start verification
    QDBusReply<void> verifyReply = m_fprintdDevice->call("VerifyStart", "any");
    if (!verifyReply.isValid()) {
        qWarning() << "[SecurityManager] Failed to start fingerprint verification:"
                   << verifyReply.error().message();
        m_fprintdDevice->call("Release");
        emit authenticationFailed("Fingerprint verification failed to start");
        return;
    }

    m_fprintdAuthInProgress = true;
    emit biometricPrompt("Place your finger on the sensor");
}

void SecurityManager::stopFingerprintAuth() {
    if (!m_fprintdDevice || !m_fprintdAuthInProgress) {
        return;
    }

    qDebug() << "[SecurityManager] Stopping fingerprint authentication";

    m_fprintdDevice->call("VerifyStop");
    m_fprintdDevice->call("Release");
    m_fprintdAuthInProgress = false;
}

void SecurityManager::cancelAuthentication() {
    stopFingerprintAuth();
}

void SecurityManager::onFingerprintVerifyStatus(const QString &result, bool done) {
    qDebug() << "[SecurityManager] Fingerprint verify status:" << result << "done:" << done;

    if (result == "verify-match") {
        stopFingerprintAuth();
        resetFailedAttempts();
        emit authenticationSuccess();
    } else if (result == "verify-no-match") {
        stopFingerprintAuth();
        recordFailedAttempt();

        QString message = "Fingerprint not recognized";
        if (m_isLockedOut) {
            int remaining = lockoutSecondsRemaining();
            message = QString("Too many failed attempts. Locked for %1 seconds.").arg(remaining);
        }

        emit authenticationFailed(message);
    } else if (result == "verify-retry-scan") {
        emit biometricPrompt("Scan quality poor, try again");
    } else if (result == "verify-swipe-too-short") {
        emit biometricPrompt("Swipe too short, try again");
    } else if (result == "verify-finger-not-centered") {
        emit biometricPrompt("Center your finger and try again");
    } else if (result == "verify-remove-and-retry") {
        emit biometricPrompt("Remove finger and try again");
    }
}

// ============================================================================
// Rate Limiting and Lockout
// ============================================================================

void SecurityManager::updateLockoutStatus() {
    // Query pam_faillock for current status
    int attempts = queryFaillockAttempts();

    if (attempts != m_failedAttempts) {
        m_failedAttempts = attempts;
        emit failedAttemptsChanged();
    }

    // Simple lockout: 5 attempts = 5 minutes
    if (m_failedAttempts >= 5) {
        if (!m_isLockedOut) {
            m_isLockedOut  = true;
            m_lockoutUntil = QDateTime::currentDateTime().addSecs(300); // 5 minutes
            m_lockoutTimer->start();
            emit lockoutStateChanged();
            qWarning() << "[SecurityManager] Account locked out for 5 minutes";
        }
    }
}

int SecurityManager::queryFaillockAttempts() {
    // Query faillock command for current user
    QString  username = getCurrentUsername();
    QProcess process;
    process.start("faillock", QStringList() << "--user" << username);
    process.waitForFinished(1000);

    QString output = process.readAllStandardOutput();

    // Parse output for failure count
    // Example: "When                Type  Source                                           Valid"
    //          "2024-11-09 12:34:56 TTY   marathon-shell                                   V"
    int count = 0;
    for (const QString &line : output.split('\n')) {
        if (line.contains("marathon-shell")) {
            count++;
        }
    }

    return count;
}

void SecurityManager::recordFailedAttempt() {
    m_failedAttempts++;
    emit failedAttemptsChanged();

    qDebug() << "[SecurityManager] Failed attempt recorded. Total:" << m_failedAttempts;

    updateLockoutStatus();
}

void SecurityManager::resetFailedAttempts() {
    if (m_failedAttempts > 0) {
        // Reset faillock for user
        QString username = getCurrentUsername();
        QProcess::execute("faillock", QStringList() << "--user" << username << "--reset");

        m_failedAttempts = 0;
        emit failedAttemptsChanged();
        qDebug() << "[SecurityManager] Failed attempts reset";
    }

    if (m_isLockedOut) {
        m_isLockedOut  = false;
        m_lockoutUntil = QDateTime();
        m_lockoutTimer->stop();
        emit lockoutStateChanged();
        qDebug() << "[SecurityManager] Lockout cleared";
    }
}

void SecurityManager::resetLockout() {
    resetFailedAttempts();
}

void SecurityManager::checkLockoutTimer() {
    if (m_isLockedOut && m_lockoutUntil.isValid()) {
        if (QDateTime::currentDateTime() >= m_lockoutUntil) {
            m_isLockedOut  = false;
            m_lockoutUntil = QDateTime();
            m_lockoutTimer->stop();
            emit lockoutStateChanged();
            qDebug() << "[SecurityManager] Lockout period expired";
        } else {
            emit lockoutStateChanged(); // Update UI with remaining time
        }
    }
}

// ============================================================================
// Helper Methods
// ============================================================================

QString SecurityManager::getCurrentUsername() const {
    uid_t          uid = getuid();
    struct passwd *pw  = getpwuid(uid);

    if (pw) {
        return QString::fromUtf8(pw->pw_name);
    }

    qWarning() << "[SecurityManager] Could not determine username";
    return QString();
}
