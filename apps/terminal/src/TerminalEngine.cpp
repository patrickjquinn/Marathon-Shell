#include "TerminalEngine.h"
#include <QDebug>
#include <QStandardPaths>
#include <QDir>
#include <QProcessEnvironment>

#ifdef Q_OS_MACOS
#include <signal.h>
#include <sys/types.h>
#endif

TerminalEngine::TerminalEngine(QObject *parent)
    : QObject(parent)
    , m_process(nullptr)
    , m_output("")
    , m_workingDirectory(QDir::homePath())
{
    qDebug() << "[TerminalEngine] Initialized";
}

TerminalEngine::~TerminalEngine()
{
    if (m_process) {
        m_process->terminate();
        m_process->waitForFinished(1000);
        m_process->deleteLater();
    }
}

QString TerminalEngine::getDefaultShell()
{
#ifdef Q_OS_MACOS
    // macOS typically uses zsh or bash
    QString shell = qEnvironmentVariable("SHELL");
    if (!shell.isEmpty()) {
        return shell;
    }
    return "/bin/zsh";
#else
    // Linux
    QString shell = qEnvironmentVariable("SHELL");
    if (!shell.isEmpty()) {
        return shell;
    }
    return "/bin/bash";
#endif
}

void TerminalEngine::setWorkingDirectory(const QString &dir)
{
    if (m_workingDirectory != dir) {
        m_workingDirectory = dir;
        if (m_process) {
            m_process->setWorkingDirectory(dir);
        }
        emit workingDirectoryChanged();
    }
}

void TerminalEngine::start()
{
    if (m_process) {
        qWarning() << "[TerminalEngine] Process already running";
        return;
    }
    
    m_process = new QProcess(this);
    m_process->setWorkingDirectory(m_workingDirectory);
    
    // CRITICAL: Separate the process channels from parent
    // This prevents the child shell from stealing the parent terminal's stdin/stdout
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->setInputChannelMode(QProcess::ManagedInputChannel);
    
    // Set up environment
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert("TERM", "xterm-256color");
    env.insert("COLORTERM", "truecolor");
    // Prevent inheriting terminal control
    env.remove("TERMINFO");
    env.remove("TERM_PROGRAM");
    m_process->setProcessEnvironment(env);
    
    // Connect signals
    connect(m_process, &QProcess::readyReadStandardOutput, this, &TerminalEngine::handleReadyRead);
    connect(m_process, &QProcess::readyReadStandardError, this, &TerminalEngine::handleReadyRead);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), 
            this, &TerminalEngine::handleFinished);
    connect(m_process, &QProcess::errorOccurred, this, &TerminalEngine::handleError);
    
    // Start shell in non-interactive mode (no TTY)
    QString shell = getDefaultShell();
    qDebug() << "[TerminalEngine] Starting shell:" << shell;
    
    // Start shell WITHOUT terminal control flags
    // This creates a "dumb" shell that doesn't try to control a TTY
    m_process->start(shell, QStringList());
    
    if (!m_process->waitForStarted(3000)) {
        qWarning() << "[TerminalEngine] Failed to start shell:" << m_process->errorString();
        return;
    }
    
    qDebug() << "[TerminalEngine] Shell started successfully (PID:" << m_process->processId() << ")";
    
    // Send initial prompt
    m_output = "Marathon Terminal\n";
    m_output += "Type 'help' for available commands\n\n";
    emit outputChanged();
    emit runningChanged();
}

void TerminalEngine::sendInput(const QString &text)
{
    if (!m_process || m_process->state() != QProcess::Running) {
        qWarning() << "[TerminalEngine] Cannot send input - process not running";
        return;
    }
    
    QString input = text;
    if (!input.endsWith('\n')) {
        input += '\n';
    }
    
    QByteArray data = input.toUtf8();
    qint64 written = m_process->write(data);
    
    if (written != data.size()) {
        qWarning() << "[TerminalEngine] Write failed - expected" << data.size() << "bytes, wrote" << written;
    } else {
        qDebug() << "[TerminalEngine] Sent input:" << text;
    }
}

void TerminalEngine::sendCtrlC()
{
    if (!m_process || m_process->state() != QProcess::Running) {
        return;
    }
    
#ifdef Q_OS_MACOS
    // Send SIGINT (Ctrl+C)
    ::kill(m_process->processId(), SIGINT);
#else
    // Linux - send Ctrl+C character
    m_process->write("\x03");
#endif
    
    qDebug() << "[TerminalEngine] Sent Ctrl+C";
}

void TerminalEngine::sendCtrlD()
{
    if (!m_process || m_process->state() != QProcess::Running) {
        return;
    }
    
    // Send EOF (Ctrl+D)
    m_process->write("\x04");
    qDebug() << "[TerminalEngine] Sent Ctrl+D";
}

void TerminalEngine::clear()
{
    m_output.clear();
    emit outputChanged();
    
    // Send clear command to terminal
    if (m_process && m_process->state() == QProcess::Running) {
        m_process->write("clear\n");
    }
}

void TerminalEngine::terminate()
{
    if (m_process) {
        m_process->terminate();
        if (!m_process->waitForFinished(1000)) {
            m_process->kill();
        }
    }
}

void TerminalEngine::handleReadyRead()
{
    if (!m_process) return;
    
    // Read stdout
    QByteArray stdoutData = m_process->readAllStandardOutput();
    if (!stdoutData.isEmpty()) {
        QString text = QString::fromUtf8(stdoutData);
        m_output += text;
        emit newOutput(text);
        emit outputChanged();
    }
    
    // Read stderr
    QByteArray stderrData = m_process->readAllStandardError();
    if (!stderrData.isEmpty()) {
        QString text = QString::fromUtf8(stderrData);
        m_output += text;
        emit newOutput(text);
        emit outputChanged();
    }
}

void TerminalEngine::handleFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    qDebug() << "[TerminalEngine] Process finished with exit code:" << exitCode 
             << "status:" << (exitStatus == QProcess::NormalExit ? "normal" : "crashed");
    
    emit processExited(exitCode);
    emit runningChanged();
}

void TerminalEngine::handleError(QProcess::ProcessError error)
{
    QString errorMsg;
    switch (error) {
        case QProcess::FailedToStart:
            errorMsg = "Failed to start shell";
            break;
        case QProcess::Crashed:
            errorMsg = "Shell crashed";
            break;
        case QProcess::Timedout:
            errorMsg = "Shell timed out";
            break;
        case QProcess::WriteError:
            errorMsg = "Write error";
            break;
        case QProcess::ReadError:
            errorMsg = "Read error";
            break;
        default:
            errorMsg = "Unknown error";
    }
    
    qWarning() << "[TerminalEngine] Error:" << errorMsg;
    m_output += "\n[ERROR] " + errorMsg + "\n";
    emit outputChanged();
}

