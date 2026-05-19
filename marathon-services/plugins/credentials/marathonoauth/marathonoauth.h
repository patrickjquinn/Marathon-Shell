#ifndef MARATHONOAUTH_PLUGIN_H
#define MARATHONOAUTH_PLUGIN_H

#include <QPointer>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <qmailcredentials.h>

// Marathon Mail OAuth — QMF credential plugin for XOAUTH2.
//
// Loaded by messageserver5 when an account's auth method is "OAUTH2".
// Bridges QMF's IMAP / SMTP plugins to the marathon-mail-oauth Rust
// helper, which owns the actual OAuth2 PKCE flow + Secret-Service
// refresh-token storage.
//
// Wire shape per call:
//
//   IMAP/SMTP plugin needs to authenticate
//      → asks QMF for credentials
//      → QMF instantiates this plugin's MarathonOAuthCredentials
//      → init() reads account_id from QMailServiceConfiguration
//      → fork+exec /usr/bin/marathon-mail-oauth token --account-id <id>
//      → parse the JSON stdout envelope
//      → expose access_token via accessToken(), status=Ready
//      → IMAP/SMTP sends `AUTH XOAUTH2 <base64-of-username-+-token>`
//
// Token caching: a freshly minted access token typically lives ~3300s
// (Google) or ~3600s (Microsoft). We cache the token in-memory for
// `expires_in_secs - 60`. After that any new init() spawns the helper
// again — which will refresh-token its way to a new access token,
// rotating the refresh token if the provider rotates (Microsoft does).
//
// Why subprocess and not in-process Rust FFI:
//   • Crash isolation (a helper panic doesn't kill messageserver5)
//   • Sandboxing — the helper can be bwrap'd with network +
//     org.freedesktop.secrets D-Bus and nothing else
//   • Mirrors Marathon's other Rust helpers (matches the convention)
//
// Install path: this builds as
//   /usr/lib/qt6/plugins/messagingframework/credentials/libmarathonoauth.so
// which QMF's QPluginLoader finds via the standard Qt plugin search.

class MarathonOAuthCredentials : public QMailCredentialsInterface {
    Q_OBJECT

  public:
    explicit MarathonOAuthCredentials(QObject *parent = nullptr);
    ~MarathonOAuthCredentials() override;

    // QMailCredentialsInterface contract.
    bool    init(const QMailServiceConfiguration &svcCfg) override;
    Status  status() const override;
    QString lastError() const override;
    QString accessToken() const override;
    QString username() const override;

  private slots:
    void onHelperFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onHelperError(QProcess::ProcessError error);

  private:
    void               spawnHelper();

    QString            m_accountId;
    QString            m_username;
    QString            m_accessToken;
    Status             m_status = Fetching;
    QString            m_lastError;
    qint64             m_tokenExpiresAtMs = 0;
    QPointer<QProcess> m_process;
    QByteArray         m_stdoutBuf;
};

class MarathonOAuthPlugin : public QMailCredentialsPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QMailCredentialsPlugin")
    Q_INTERFACES(QMailCredentialsPlugin)

  public:
    explicit MarathonOAuthPlugin(QObject *parent = nullptr);

    QString                    key() const override;
    QMailCredentialsInterface *createCredentialsHandler(QObject *parent = nullptr) override;
};

#endif // MARATHONOAUTH_PLUGIN_H
