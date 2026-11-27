#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>

// The boot PIN pad's side of marathon-carrier-home-crypt: each PIN goes to the
// command on stdin. Once the command takes one, the pad settles back into the
// splash and release() hands the display back: it gives up DRM master with its
// last frame still on screen and says "open" on stdout, so Plymouth can take
// over before the pad is stopped.
class HomeUnlock : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

  public:
    HomeUnlock(const QStringList &command, QObject *parent);

    bool busy() const {
        return m_process.state() != QProcess::NotRunning;
    }
    Q_INVOKABLE void submit(const QString &pin);
    Q_INVOKABLE void release();

  signals:
    void busyChanged();
    void rejected();
    void opened();

  private:
    void        dropMaster();

    QStringList m_command;
    QProcess    m_process;
};
