#ifndef MARATHONCLASSIC_PLUGIN_H
#define MARATHONCLASSIC_PLUGIN_H

#include <QPointer>
#include <QProcess>
#include <QString>
#include <qmailcredentials.h>

// Marathon Mail Classic — QMF credential plugin for PLAIN/LOGIN auth.
//
// Sibling of marathonoauth. Loaded by messageserver when an account's
// CredentialsPlugin=marathon-classic. The plugin shells out to
// /usr/bin/marathon-mail-oauth classic-get --account-id <id> to fetch
// the stored username + password from Secret-Service, then exposes them
// to QMF's IMAP/SMTP services via username() + password().
//
// Why this exists: MailService.addImapAccount could in principle write
// the password directly into QMF's QSettings-backed account config. It
// did, for one commit. That stores the password as plaintext under
// ~/.config/QMF/QMF.conf and is unacceptable for a phone OS. Migrating
// retrieval through Secret-Service mirrors how marathonoauth handles
// OAuth refresh tokens — same helper binary, same isolation model.
//
// Install path:
//   /usr/lib/qt6/plugins/messagingframework/credentials/libmarathonclassic.so

class MarathonClassicCredentials : public QMailCredentialsInterface {
    Q_OBJECT

  public:
    explicit MarathonClassicCredentials(QObject *parent = nullptr);
    ~MarathonClassicCredentials() override;

    bool    init(const QMailServiceConfiguration &svcCfg) override;
    Status  status() const override;
    QString lastError() const override;
    QString username() const override;
    QString password() const override;

  private slots:
    void onHelperFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onHelperError(QProcess::ProcessError error);

  private:
    void               spawnHelper();

    QString            m_accountId;
    QString            m_username;
    QString            m_password;
    Status             m_status = Fetching;
    QString            m_lastError;
    QPointer<QProcess> m_process;
    QByteArray         m_stdoutBuf;
};

class MarathonClassicPlugin : public QMailCredentialsPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QMailCredentialsPlugin")
    Q_INTERFACES(QMailCredentialsPlugin)

  public:
    explicit MarathonClassicPlugin(QObject *parent = nullptr);

    QString                    key() const override;
    QMailCredentialsInterface *createCredentialsHandler(QObject *parent = nullptr) override;
};

#endif // MARATHONCLASSIC_PLUGIN_H
