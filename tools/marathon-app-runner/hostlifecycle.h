#pragma once

#include <QDBusConnection>
#include <QDBusContext>
#include <QObject>

class KeelHost;

// The shell's per-app calls (org.marathonos.AppRunner.Lifecycle1, as the
// runner serves them) for an app under marathon-keel-host: what the shell
// shows of the app becomes the Keel host's Active and CoverStatus.
class HostLifecycle : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.AppRunner.Lifecycle1")

  public:
    HostLifecycle(KeelHost *host, qint64 shellPid, QObject *parent = nullptr);

    static QString serviceName(const QString &appId);
    bool           registerOn(QDBusConnection bus, const QString &appId);

  public slots:
    void SetActive(bool active);
    void SetCoverStatus(int status);

  private:
    bool      callerIsShell();

    KeelHost *m_host;
    qint64    m_shellPid;
};
