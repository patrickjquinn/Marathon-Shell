#ifndef UPDATESERVICE_H
#define UPDATESERVICE_H

#include <QObject>
#include <QString>
#include <QPointer>
#include <QTimer>

class QNetworkAccessManager;
class QNetworkReply;

// Polls the GitHub Releases API for newer Marathon Shell builds and surfaces
// the result to QML so the Settings UI can show a "Tap to update" banner.
//
// We deliberately don't host any custom server: GitHub Releases is the apk
// repo, and the device's `apk` (postmarketOS) handles the actual install.
// All this class does is the version compare + the user-facing tile.
//
// Settings keys consumed (via SettingsManager):
//   "updates/feedRepo"   -- owner/repo, default "patrickjquinn/Marathon-Shell"
//   "updates/channel"    -- "stable" (release) or "edge" (pre-release allowed)
//   "updates/autoCheck"  -- bool, default true
class UpdateService : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY latestVersionChanged)
    Q_PROPERTY(QString releaseUrl READ releaseUrl NOTIFY latestVersionChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY latestVersionChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY latestVersionChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY checkingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

  public:
    explicit UpdateService(QObject *parent = nullptr);

    QString currentVersion() const {
        return m_currentVersion;
    }
    QString latestVersion() const {
        return m_latestVersion;
    }
    QString releaseUrl() const {
        return m_releaseUrl;
    }
    QString releaseNotes() const {
        return m_releaseNotes;
    }
    bool updateAvailable() const;
    bool checking() const {
        return m_checking;
    }
    QString lastError() const {
        return m_lastError;
    }

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void openInBrowser();
    Q_INVOKABLE bool isStableChannel() const;
    Q_INVOKABLE void setChannel(const QString &channel);

  signals:
    void latestVersionChanged();
    void checkingChanged();
    void lastErrorChanged();
    void updateInstallStarted();
    void updateInstallFinished(bool success, const QString &message);

  private slots:
    void onReleasesReply();

  private:
    static int              compareVersion(const QString &a, const QString &b);

    QString                 m_currentVersion;
    QString                 m_latestVersion;
    QString                 m_releaseUrl;
    QString                 m_releaseNotes;
    QString                 m_lastError;
    bool                    m_checking = false;

    QNetworkAccessManager  *m_net;
    QPointer<QNetworkReply> m_reply;
    QTimer                 *m_autoCheckTimer;
};

#endif
