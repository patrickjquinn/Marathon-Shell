#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>

class KeelHost;

// A native Keel app (a Sailfish app rebuilt on Keel's sailfishapp) run as a
// child of a Keel host: it gets the protocol environment, and closing it
// sends CloseRequested and waits before stopping it.
class HostedApp : public QObject {
    Q_OBJECT

  public:
    HostedApp(KeelHost *host, const QString &program, const QStringList &arguments,
              int closeGraceMs = 1000, QObject *parent = nullptr);

    bool start();
    void close();

  signals:
    void finished(int exitCode);

  private:
    KeelHost   *m_host;
    QProcess    m_process;
    QString     m_program;
    QStringList m_arguments;
    int         m_closeGraceMs;
    bool        m_closing = false;
};
