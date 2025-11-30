#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QVariantMap>

/**
 * @brief MarathonAppProcess - Runs a Marathon app in a separate process
 * 
 * This provides true process isolation - if an app crashes, it won't take
 * down the shell. Each app runs in its own QProcess with proper lifecycle
 * management and IPC.
 */
class MarathonAppProcess : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString appId READ appId CONSTANT)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int exitCode READ exitCode NOTIFY exitCodeChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)

  public:
    explicit MarathonAppProcess(const QString &appId, QObject *parent = nullptr);
    ~MarathonAppProcess() override;

    QString appId() const {
        return m_appId;
    }
    bool running() const;
    int  exitCode() const {
        return m_exitCode;
    }
    QString errorString() const {
        return m_errorString;
    }

    // Start the app in a separate process
    Q_INVOKABLE bool start(const QString &appPath, const QString &entryPoint);

    // Stop the app (graceful)
    Q_INVOKABLE void stop();

    // Kill the app (forceful)
    Q_INVOKABLE void kill();

    // Restart the app
    Q_INVOKABLE void restart();

  signals:
    void runningChanged();
    void exitCodeChanged();
    void errorStringChanged();
    void started();
    void finished(int exitCode, QProcess::ExitStatus exitStatus);
    void crashed();
    void errorOccurred(QProcess::ProcessError error);

  private slots:
    void handleStarted();
    void handleFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void handleErrorOccurred(QProcess::ProcessError error);
    void handleStateChanged(QProcess::ProcessState state);

  private:
    QString          m_appId;
    QProcess        *m_process;
    QString          m_appPath;
    QString          m_entryPoint;
    int              m_exitCode;
    QString          m_errorString;
    int              m_crashCount;
    static const int MAX_CRASHES = 3;
};
