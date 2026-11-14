// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// SIGTERM/SIGINT/SIGHUP -> Qt signal (self-pipe). Lipstick terminates an app
// by sending SIGTERM to the pid that owns its window, which is keel-shell;
// keel-shell must pass that on to the nested app and exit cleanly.

#ifndef KEEL_UNIXSIGNALS_H
#define KEEL_UNIXSIGNALS_H

#include <QObject>
#include <QString>

class QSocketNotifier;

namespace keel {

class UnixSignals : public QObject
{
    Q_OBJECT
public:
    explicit UnixSignals(QObject *parent = nullptr);
    ~UnixSignals() override;

    // False if the self-pipe could not be created. No handlers are installed
    // then, and SIGTERM would kill keel-shell without stopping the app, so
    // main() refuses to start.
    bool isValid() const { return m_notifier != nullptr; }
    QString errorString() const { return m_error; }

signals:
    void terminateRequested(int signalNumber);

private slots:
    void onActivated();

private:
    static void handler(int signalNumber);
    static int s_fds[2];
    QSocketNotifier *m_notifier = nullptr;
    QString m_error;
};

} // namespace keel

#endif // KEEL_UNIXSIGNALS_H
