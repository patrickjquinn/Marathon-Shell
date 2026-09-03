#include "marathonoauth.h"

#include <QDateTime>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <qmailaccountconfiguration.h>

namespace {
    // Helper invocation: /usr/bin/marathon-mail-oauth token --account-id <id>
    // Output (single JSON line on stdout):
    //   { "kind": "access_token",
    //     "access_token": "...",
    //     "expires_in_secs": 3300,
    //     "email": "user@example.com" | null }
    // On error:
    //   { "kind": "error", "code": "...", "message": "..." }
    constexpr const char *kHelperBinary    = "/usr/bin/marathon-mail-oauth";
    constexpr int         kCacheMarginSecs = 60;
} // namespace

MarathonOAuthCredentials::MarathonOAuthCredentials(QObject *parent)
    : QMailCredentialsInterface(parent) {}

MarathonOAuthCredentials::~MarathonOAuthCredentials() {
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(500);
    }
}

bool MarathonOAuthCredentials::init(const QMailServiceConfiguration &svcCfg) {
    QMailCredentialsInterface::init(svcCfg);

    // The account_id we pass to the helper is the string-form of the QMF
    // QMailAccountId.toULongLong(). marathon-mail-oauth indexes its
    // Secret-Service items by exactly this key (see
    // tools/marathon-mail-oauth/src/main.rs).
    m_accountId = QString::number(id().toULongLong());
    m_username  = svcCfg.value(QStringLiteral("username"));

    // Cache check — if we have a fresh token, skip the helper roundtrip.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!m_accessToken.isEmpty() && now < m_tokenExpiresAtMs) {
        m_status = Ready;
        emit statusChanged();
        return true;
    }

    spawnHelper();
    return true;
}

void MarathonOAuthCredentials::spawnHelper() {
    if (m_process && m_process->state() != QProcess::NotRunning) {
        // A previous invocation is still in flight. Don't double-spawn —
        // QMF's auth path is reentrant-safe and will call init() again
        // if status doesn't flip to Ready in time.
        return;
    }

    m_status = Fetching;
    m_stdoutBuf.clear();
    m_lastError.clear();

    auto *proc = new QProcess(this);
    proc->setProgram(QString::fromUtf8(kHelperBinary));
    proc->setArguments({QStringLiteral("token"), QStringLiteral("--account-id"), m_accountId});
    proc->setProcessChannelMode(QProcess::SeparateChannels);

    connect(proc, &QProcess::readyReadStandardOutput, this,
            [this, proc] { m_stdoutBuf.append(proc->readAllStandardOutput()); });
    connect(proc, &QProcess::finished, this, &MarathonOAuthCredentials::onHelperFinished);
    connect(proc, &QProcess::errorOccurred, this, &MarathonOAuthCredentials::onHelperError);

    m_process = proc;
    proc->start();
    emit statusChanged();
}

void MarathonOAuthCredentials::onHelperError(QProcess::ProcessError error) {
    m_status    = Failed;
    m_lastError = QStringLiteral("marathon-mail-oauth process error: %1").arg(int(error));
    if (m_process) {
        m_process->deleteLater();
        m_process = nullptr;
    }
    emit statusChanged();
}

void MarathonOAuthCredentials::onHelperFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    if (m_process) {
        // Drain any tail.
        m_stdoutBuf.append(m_process->readAllStandardOutput());
        m_process->deleteLater();
        m_process = nullptr;
    }

    if (exitStatus != QProcess::NormalExit) {
        m_status    = Failed;
        m_lastError = QStringLiteral("marathon-mail-oauth crashed");
        emit statusChanged();
        return;
    }

    // The helper writes one JSON envelope per line. We only care about the
    // last one — but typically there's only one.
    const QList<QByteArray> lines = m_stdoutBuf.split('\n');
    QByteArray              last;
    for (const auto &line : lines)
        if (!line.trimmed().isEmpty())
            last = line;

    QJsonParseError parseErr{};
    const auto      doc = QJsonDocument::fromJson(last, &parseErr);
    if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
        m_status = Failed;
        m_lastError =
            QStringLiteral("marathon-mail-oauth: malformed JSON: %1").arg(parseErr.errorString());
        emit statusChanged();
        return;
    }

    const auto obj  = doc.object();
    const auto kind = obj.value(QStringLiteral("kind")).toString();

    if (kind == QStringLiteral("error")) {
        m_status    = Failed;
        m_lastError = obj.value(QStringLiteral("message"))
                          .toString(QStringLiteral("(unspecified helper error)"));
        emit statusChanged();
        return;
    }

    if (kind != QStringLiteral("access_token")) {
        m_status    = Failed;
        m_lastError = QStringLiteral("marathon-mail-oauth: unexpected reply kind '%1'").arg(kind);
        emit statusChanged();
        return;
    }

    m_accessToken = obj.value(QStringLiteral("access_token")).toString();
    if (m_accessToken.isEmpty()) {
        m_status    = Failed;
        m_lastError = QStringLiteral("marathon-mail-oauth returned empty access_token");
        emit statusChanged();
        return;
    }

    const auto expiresIn = obj.value(QStringLiteral("expires_in_secs")).toInt(3300);
    m_tokenExpiresAtMs =
        QDateTime::currentMSecsSinceEpoch() + qint64(qMax(0, expiresIn - kCacheMarginSecs)) * 1000;

    // Helper may have supplied an email — if we didn't get a username from
    // the service config, use that instead. QMF needs SOMETHING for the
    // XOAUTH2 SASL string ("user=<email>\x01auth=Bearer <token>\x01\x01").
    const auto email = obj.value(QStringLiteral("email")).toString();
    if (m_username.isEmpty() && !email.isEmpty())
        m_username = email;

    m_status = Ready;
    m_lastError.clear();
    Q_UNUSED(exitCode);
    emit statusChanged();
}

QMailCredentialsInterface::Status MarathonOAuthCredentials::status() const {
    return m_status;
}

QString MarathonOAuthCredentials::lastError() const {
    return m_lastError;
}

QString MarathonOAuthCredentials::accessToken() const {
    return m_accessToken;
}

QString MarathonOAuthCredentials::username() const {
    return m_username;
}

// ── Plugin registration ──────────────────────────────────────────────

MarathonOAuthPlugin::MarathonOAuthPlugin(QObject *parent)
    : QMailCredentialsPlugin(parent) {}

QString MarathonOAuthPlugin::key() const {
    // QMF resolves a credentials handler by string key. Marathon's account
    // configuration sets `CredentialsPlugin=marathon-oauth` for accounts
    // we provision through marathon-mail-oauth — those go to this handler.
    // Anything else falls back to the SSO / password handler that QMF
    // ships with.
    return QStringLiteral("marathon-oauth");
}

QMailCredentialsInterface *MarathonOAuthPlugin::createCredentialsHandler(QObject *parent) {
    return new MarathonOAuthCredentials(parent);
}
