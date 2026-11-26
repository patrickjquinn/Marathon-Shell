#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>

// The boot PIN pad's side of marathon-carrier-home-crypt: each PIN goes to the
// command on stdin, and the pad quits once the command takes one.
class HomeUnlock : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

  public:
    HomeUnlock(const QStringList &command, QObject *parent);

    bool busy() const {
        return m_process.state() != QProcess::NotRunning;
    }
    Q_INVOKABLE void submit(const QString &pin);

  signals:
    void busyChanged();
    void rejected();

  private:
    QStringList m_command;
    QProcess    m_process;
};
