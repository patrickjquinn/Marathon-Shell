/****************************************************************************
**
** SPDX-FileCopyrightText: 2020 Rinigus https://github.com/rinigus
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Derived from qt-runner src/runner.h (BSD-3-Clause). Modified for
** Shipwright keel-shell: environment is built by keel::LaunchConfig, exit
** code is propagated, graceful close with a grace period. See PROVENANCE.md.
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are
** met:
**   * Redistributions of source code must retain the above copyright
**     notice, this list of conditions and the following disclaimer.
**   * Redistributions in binary form must reproduce the above copyright
**     notice, this list of conditions and the following disclaimer in
**     the documentation and/or other materials provided with the
**     distribution.
**   * Neither the name of the copyright holder nor the names of its
**     contributors may be used to endorse or promote products derived
**     from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
** "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
** LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
** A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
** OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
** SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
** LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
** DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
** THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
** OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************/

#ifndef KEEL_RUNNER_H
#define KEEL_RUNNER_H

#include <QObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStringList>
#include <QTimer>

namespace keel {

class Runner : public QObject
{
    Q_OBJECT
public:
    Runner(QString program, QStringList arguments,
           const QProcessEnvironment &env, QObject *parent = nullptr);

    void start();
    // Asks politely (caller emits CloseRequested first), then SIGTERM after
    // graceMs, then SIGKILL after a further kKillAfterTermMs.
    static constexpr int kKillAfterTermMs = 5000;
    void stop(int graceMs);

    bool running() const { return m_process->state() != QProcess::NotRunning; }
    qint64 pid() const;
    int exitCode() const { return m_exitCode; }
    // True once stop() was called: a signal death is then expected.
    bool stopping() const { return m_stopping; }
    bool crashed() const { return m_crashed; }

signals:
    void started();
    void exited(int exitCode, bool crashed);

private slots:
    void onError(QProcess::ProcessError error);
    void onFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStdErr();
    void onStdOut();

private:
    QProcess *m_process;
    QString m_program;
    QStringList m_arguments;
    QTimer m_termTimer;
    QTimer m_killTimer;
    int m_exitCode = 0;
    bool m_crashed = false;
    bool m_finished = false;
    bool m_stopping = false;
};

} // namespace keel

#endif // KEEL_RUNNER_H
