/****************************************************************************
**
** SPDX-FileCopyrightText: 2020 Rinigus https://github.com/rinigus
** SPDX-FileCopyrightText: 2026 Patrick Quinn
** SPDX-License-Identifier: BSD-3-Clause
**
** Derived from qt-runner src/runner.cpp (BSD-3-Clause). Full licence text
** in runner.h and upstream-licenses/. See PROVENANCE.md.
**
****************************************************************************/

#include "runner.h"

#include <iostream>
#include <utility>

#include "logging.h"

namespace keel {

Runner::Runner(QString program, QStringList arguments,
               const QProcessEnvironment &env, QObject *parent)
    : QObject(parent)
    , m_process(new QProcess(this))
    , m_program(std::move(program))
    , m_arguments(std::move(arguments))
{
    m_process->setProcessEnvironment(env);
    connect(m_process, &QProcess::errorOccurred, this, &Runner::onError);
    connect(m_process, &QProcess::readyReadStandardError, this, &Runner::onStdErr);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &Runner::onStdOut);
    connect(m_process, &QProcess::started, this, &Runner::started);
    connect(m_process,
            static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
            this, &Runner::onFinished);

    m_termTimer.setSingleShot(true);
    m_killTimer.setSingleShot(true);
    m_killTimer.setInterval(kKillAfterTermMs);
    connect(&m_termTimer, &QTimer::timeout, this, [this]() {
        if (running()) {
            qCInfo(lcKeelShell) << "sending SIGTERM to the app";
            m_process->terminate();
            m_killTimer.start();
        }
    });
    connect(&m_killTimer, &QTimer::timeout, this, [this]() {
        if (running()) {
            qCWarning(lcKeelShell) << "app ignored SIGTERM, killing it";
            m_process->kill();
        }
    });
}

void Runner::start()
{
    m_process->start(m_program, m_arguments);
}

qint64 Runner::pid() const
{
    return m_process->processId();
}

void Runner::stop(int graceMs)
{
    if (!running())
        return;
    m_stopping = true;
    if (!m_termTimer.isActive() && !m_killTimer.isActive())
        m_termTimer.start(qMax(0, graceMs));
}

void Runner::onError(QProcess::ProcessError error)
{
    qCWarning(lcKeelShell).noquote() << m_process->errorString();
    if (error == QProcess::FailedToStart) {
        m_finished = true;
        m_exitCode = 127;
        emit exited(m_exitCode, false);
    }
}

void Runner::onFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onStdErr();
    onStdOut();
    m_termTimer.stop();
    m_killTimer.stop();
    if (m_finished)
        return;
    m_finished = true;
    // A SIGTERM/SIGKILL we sent ourselves is not a crash.
    m_crashed = (exitStatus == QProcess::CrashExit) && !m_stopping;
    if (exitStatus == QProcess::CrashExit && m_stopping)
        exitCode = 0;
    m_exitCode = exitCode;
    emit exited(exitCode, m_crashed);
}

void Runner::onStdErr()
{
    std::cerr << m_process->readAllStandardError().constData() << std::flush;
}

void Runner::onStdOut()
{
    std::cout << m_process->readAllStandardOutput().constData() << std::flush;
}

} // namespace keel
