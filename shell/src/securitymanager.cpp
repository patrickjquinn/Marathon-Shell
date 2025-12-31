#include "securitymanager.h"
#include "securitylogger.h"
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
    SecurityLogger::initialize();

    qDebug() << "[SecurityManager] Initializing authentication system";

    initFingerprintDevice();

    m_hasQuickPIN = !retrieveQuickPIN().isEmpty();

    m_lockoutTimer->setInterval(1000);
    connect(m_lockoutTimer, &QTimer::timeout, this, &SecurityManager::checkLockoutTimer);

    connect(m_passwordAuthWatcher, &QFutureWatcher<bool>::finished, this,
            &SecurityManager::onPasswordAuthFinished);
    connect(m_quickPINAuthWatcher, &QFutureWatcher<bool>::finished, this,
            &SecurityManager::onQuickPINAuthFinished);

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
            case PAM_PROMPT_ECHO_OFF:
            case PAM_PROMPT_ECHO_ON:
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

    int ret = pam_start("marathon-shell", username.toUtf8().constData(), &conv, &pamh);
    if (ret != PAM_SUCCESS) {
        qWarning() << "[SecurityManager] PAM start failed:" << pam_strerror(pamh, ret);
        m_currentPassword.clear();
        return false;
    }

    ret = pam_authenticate(pamh, PAM_SILENT);
    if (ret != PAM_SUCCESS) {
        qWarning() << "[SecurityManager] PAM authentication failed:" << pam_strerror(pamh, ret);
        pam_end(pamh, ret);
        m_currentPassword.clear();
        return false;
    }

    ret = pam_acct_mgmt(pamh, PAM_SILENT);
    if (ret != PAM_SUCCESS) {
        qWarning() << "[SecurityManager] PAM account management failed:" << pam_strerror(pamh, ret);
        pam_end(pamh, ret);
        m_currentPassword.clear();
        return false;
    }

    pam_end(pamh, PAM_SUCCESS);
    m_currentPassword.clear();

    qDebug() << "[SecurityManager] PAM authentication successful";
    return true;
}

void SecurityManager::authenticatePassword(const QString &password) {
    qDebug() << "[SecurityManager] Password authentication requested";

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

    m_currentPassword = password;

    qDebug() << "[SecurityManager] Starting async PAM authentication";
    QFuture<bool> future =
        QtConcurrent::run([this, password]() { return authenticateViaPAM(password); });

    m_passwordAuthWatcher->setFuture(future);
}

void SecurityManager::onPasswordAuthFinished() {
    bool    success  = m_passwordAuthWatcher->result();
    QString username = getCurrentUsername();
    m_currentPassword.clear();

    qDebug() << "[SecurityManager] Async PAM authentication completed, success:" << success;

    if (success) {
        resetFailedAttempts();
        SecurityLogger::logAuthSuccess(username, "password");
        emit authenticationSuccess();
    } else {
        recordFailedAttempt();
        SecurityLogger::logAuthFailure(username, "Invalid password", "PAM");

        QString message = "Incorrect password";
        if (m_isLockedOut) {
            int remaining = lockoutSecondsRemaining();
            message = QString("Too many failed attempts. Locked for %1 seconds.").arg(remaining);
            SecurityLogger::logAuthLockout(username, remaining);
        } else if (m_failedAttempts > 0) {
            int remaining = 5 - m_failedAttempts;
            message += QString(" (%1 attempts remaining)").arg(remaining);
        }

        emit authenticationFailed(message);
    }
}

QByteArray SecurityManager::generateSalt(int length) {
    QByteArray salt;
    salt.resize(length);
    for (int i = 0; i < length; ++i) {
        salt[i] = static_cast<char>(QRandomGenerator::securelySeeded().bounded(256));
    }
    return salt;
}

QByteArray SecurityManager::hashWithIterations(const QByteArray &data, int iterations) {
    QByteArray result = data;
    for (int i = 0; i < iterations; ++i) {
        result = QCryptographicHash::hash(result, QCryptographicHash::Sha256);
    }
    return result;
}

QString SecurityManager::retrieveQuickPIN() {
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

    QString contents = QString::fromUtf8(file.readAll()).trimmed();
    file.close();

    return contents;
}

bool SecurityManager::storeQuickPIN(const QString &pin) {
    static constexpr int SALT_LENGTH = 32;
    static constexpr int ITERATIONS  = 10000;

    QByteArray           salt      = generateSalt(SALT_LENGTH);
    QByteArray           saltedPin = salt + pin.toUtf8();
    QByteArray           hash      = hashWithIterations(saltedPin, ITERATIONS);

    QString              storedValue =
        QString::fromLatin1(salt.toHex()) + ":" + QString::fromLatin1(hash.toHex());

    QString configPath =
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/marathon";
    QDir().mkpath(configPath);

    QString filePath = configPath + "/quickpin.conf";
    QFile   file(filePath);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[SecurityManager] Could not write Quick PIN file";
        return false;
    }

    file.write(storedValue.toUtf8());
    file.close();
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
    static constexpr int ITERATIONS = 10000;

    QString              storedData = retrieveQuickPIN();
    if (storedData.isEmpty()) {
        return false;
    }

    QStringList parts = storedData.split(':');
    if (parts.size() != 2) {
        qWarning() << "[SecurityManager] Legacy PIN format detected";
        QByteArray hash = QCryptographicHash::hash(pin.toUtf8(), QCryptographicHash::Sha256);
        return QString::fromLatin1(hash.toHex()) == storedData;
    }

    QByteArray salt         = QByteArray::fromHex(parts[0].toLatin1());
    QByteArray storedHash   = QByteArray::fromHex(parts[1].toLatin1());
    QByteArray saltedPin    = salt + pin.toUtf8();
    QByteArray computedHash = hashWithIterations(saltedPin, ITERATIONS);

    if (computedHash.size() != storedHash.size()) {
        return false;
    }

    volatile int result = 0;
    for (int i = 0; i < computedHash.size(); ++i) {
        result |= (computedHash[i] ^ storedHash[i]);
    }
    return result == 0;
}

void SecurityManager::authenticateQuickPIN(const QString &pin) {
    qDebug() << "[SecurityManager] Quick PIN authentication requested";

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

    qDebug() << "[SecurityManager] Starting async Quick PIN verification";
    QFuture<bool> future = QtConcurrent::run([this, pin]() { return verifyQuickPIN(pin); });

    m_quickPINAuthWatcher->setFuture(future);
}

void SecurityManager::onQuickPINAuthFinished() {
    bool    success  = m_quickPINAuthWatcher->result();
    QString username = getCurrentUsername();

    qDebug() << "[SecurityManager] Async Quick PIN verification completed, success:" << success;

    if (success) {
        resetFailedAttempts();
        SecurityLogger::logAuthSuccess(username, "quick_pin");
        emit authenticationSuccess();
    } else {
        recordFailedAttempt();
        SecurityLogger::logAuthFailure(username, "Invalid PIN", "QuickPIN");

        QString message = "Incorrect PIN";
        if (m_isLockedOut) {
            int remaining = lockoutSecondsRemaining();
            message = QString("Too many failed attempts. Locked for %1 seconds.").arg(remaining);
            SecurityLogger::logAuthLockout(username, remaining);
        } else if (m_failedAttempts > 0) {
            int remaining = 5 - m_failedAttempts;
            message += QString(" (%1 attempts remaining)").arg(remaining);
        }

        emit authenticationFailed(message);
    }
}

void SecurityManager::setQuickPIN(const QString &pin, const QString &systemPassword) {
    qDebug() << "[SecurityManager] Setting Quick PIN (requires system password verification)";

    if (!authenticateViaPAM(systemPassword)) {
        emit authenticationFailed("System password incorrect. Cannot set Quick PIN.");
        return;
    }

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

    if (!authenticateViaPAM(systemPassword)) {
        emit authenticationFailed("System password incorrect. Cannot remove Quick PIN.");
        return;
    }

    clearQuickPIN();
    m_hasQuickPIN = false;
    emit quickPINChanged();
    qDebug() << "[SecurityManager] Quick PIN removed successfully";
}

void SecurityManager::initFingerprintDevice() {
    qDebug() << "[SecurityManager] Initializing fprintd device";

    QDBusConnection systemBus = QDBusConnection::systemBus();
    if (!systemBus.interface()->isServiceRegistered("net.reactivated.Fprint")) {
        qDebug() << "[SecurityManager] fprintd service not available";
        m_fingerprintAvailable = false;
        return;
    }

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

    QDBusReply<QDBusObjectPath> reply = m_fprintdManager->call("GetDefaultDevice");
    if (!reply.isValid()) {
        qDebug() << "[SecurityManager] No fingerprint device available:" << reply.error().message();
        m_fingerprintAvailable = false;
        return;
    }

    QString devicePath = reply.value().path();
    qDebug() << "[SecurityManager] Found fingerprint device:" << devicePath;

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

    systemBus.connect("net.reactivated.Fprint", devicePath, "net.reactivated.Fprint.Device",
                      "VerifyStatus", this, SLOT(onFingerprintVerifyStatus(QString, bool)));

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
    return false;
}

void SecurityManager::authenticateBiometric(BiometricType type) {
    if (type != Fingerprint) {
        emit authenticationFailed("Biometric type not supported");
        return;
    }

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

    QDBusReply<void> claimReply = m_fprintdDevice->call("Claim", getCurrentUsername());
    if (!claimReply.isValid()) {
        qWarning() << "[SecurityManager] Failed to claim fingerprint device:"
                   << claimReply.error().message();
        emit authenticationFailed("Fingerprint device busy");
        return;
    }

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

void SecurityManager::updateLockoutStatus() {
    int attempts = queryFaillockAttempts();

    if (attempts != m_failedAttempts) {
        m_failedAttempts = attempts;
        emit failedAttemptsChanged();
    }

    if (m_failedAttempts >= 5) {
        if (!m_isLockedOut) {
            m_isLockedOut  = true;
            m_lockoutUntil = QDateTime::currentDateTime().addSecs(300);
            m_lockoutTimer->start();
            emit lockoutStateChanged();
            qWarning() << "[SecurityManager] Account locked out for 5 minutes";
        }
    }
}

int SecurityManager::queryFaillockAttempts() {
    QString  username = getCurrentUsername();
    QProcess process;
    process.start("faillock", QStringList() << "--user" << username);
    process.waitForFinished(1000);

    QString output = process.readAllStandardOutput();

    int     count = 0;
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
            emit lockoutStateChanged();
        }
    }
}

QString SecurityManager::getCurrentUsername() const {
    uid_t          uid = getuid();
    struct passwd *pw  = getpwuid(uid);

    if (pw) {
        return QString::fromUtf8(pw->pw_name);
    }

    qWarning() << "[SecurityManager] Could not determine username";
    return QString();
}
