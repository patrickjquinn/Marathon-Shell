#include "marathonclassic.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>

namespace {
    constexpr const char *kHelperBinary = "/usr/bin/marathon-mail-oauth";
} // namespace

MarathonClassicCredentials::MarathonClassicCredentials(QObject *parent)
    : QMailCredentialsInterface(parent) {}

MarathonClassicCredentials::~MarathonClassicCredentials() {
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(500);
    }
}

bool MarathonClassicCredentials::init(const QMailServiceConfiguration &svcCfg) {
    QMailCredentialsInterface::init(svcCfg);

    m_accountId = QString::number(id().toULongLong());

    // Service config username is informational only; the helper returns
    // the authoritative username from Secret-Service. We keep the
    // service-config copy as a fallback if the helper hasn't populated
    // the attribute (legacy accounts).
    m_username = svcCfg.value(QStringLiteral("username"));

    spawnHelper();
    return true;
}

void MarathonClassicCredentials::spawnHelper() {
    if (m_process && m_process->state() != QProcess::NotRunning)
        return;

    m_status = Fetching;
    m_stdoutBuf.clear();
    m_lastError.clear();

    auto *proc = new QProcess(this);
    proc->setProgram(QString::fromUtf8(kHelperBinary));
    proc->setArguments(
        {QStringLiteral("classic-get"), QStringLiteral("--account-id"), m_accountId});
    proc->setProcessChannelMode(QProcess::SeparateChannels);

    connect(proc, &QProcess::readyReadStandardOutput, this,
            [this, proc] { m_stdoutBuf.append(proc->readAllStandardOutput()); });
    connect(proc, &QProcess::finished, this, &MarathonClassicCredentials::onHelperFinished);
    connect(proc, &QProcess::errorOccurred, this, &MarathonClassicCredentials::onHelperError);

    m_process = proc;
    proc->start();
    emit statusChanged();
}

void MarathonClassicCredentials::onHelperError(QProcess::ProcessError error) {
    m_status    = Failed;
    m_lastError = QStringLiteral("marathon-mail-oauth process error: %1").arg(int(error));
    if (m_process) {
        m_process->deleteLater();
        m_process = nullptr;
    }
    emit statusChanged();
}

void MarathonClassicCredentials::onHelperFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    if (m_process) {
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

    if (kind != QStringLiteral("password")) {
        m_status    = Failed;
        m_lastError = QStringLiteral("marathon-mail-oauth: unexpected reply kind '%1'").arg(kind);
        emit statusChanged();
        return;
    }

    const auto helperUser = obj.value(QStringLiteral("username")).toString();
    if (!helperUser.isEmpty())
        m_username = helperUser;

    m_password = obj.value(QStringLiteral("password")).toString();
    if (m_password.isEmpty()) {
        m_status    = Failed;
        m_lastError = QStringLiteral("marathon-mail-oauth returned empty password");
        emit statusChanged();
        return;
    }

    m_status = Ready;
    m_lastError.clear();
    Q_UNUSED(exitCode);
    emit statusChanged();
}

QMailCredentialsInterface::Status MarathonClassicCredentials::status() const {
    return m_status;
}

QString MarathonClassicCredentials::lastError() const {
    return m_lastError;
}

QString MarathonClassicCredentials::username() const {
    return m_username;
}

QString MarathonClassicCredentials::password() const {
    return m_password;
}

// ── Plugin registration ──────────────────────────────────────────────

MarathonClassicPlugin::MarathonClassicPlugin(QObject *parent)
    : QMailCredentialsPlugin(parent) {}

QString MarathonClassicPlugin::key() const {
    return QStringLiteral("marathon-classic");
}

QMailCredentialsInterface *MarathonClassicPlugin::createCredentialsHandler(QObject *parent) {
    return new MarathonClassicCredentials(parent);
}
