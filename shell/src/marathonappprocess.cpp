#include "marathonappprocess.h"
#include <QDebug>
#include <QCoreApplication>
#include <QTimer>

MarathonAppProcess::MarathonAppProcess(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_process(nullptr)
    , m_exitCode(0)
    , m_crashCount(0) {
    qDebug() << "[AppProcess]" << m_appId << "- Process manager created";
}

MarathonAppProcess::~MarathonAppProcess() {
    if (m_process && m_process->state() != QProcess::NotRunning) {
        qDebug() << "[AppProcess]" << m_appId << "- Terminating process";
        m_process->terminate();
        if (!m_process->waitForFinished(3000)) {
            qDebug() << "[AppProcess]" << m_appId << "- Force killing process";
            m_process->kill();
            m_process->waitForFinished(1000);
        }
    }
    delete m_process;
}

bool MarathonAppProcess::running() const {
    return m_process && m_process->state() == QProcess::Running;
}

bool MarathonAppProcess::start(const QString &appPath, const QString &entryPoint) {
    if (m_process && m_process->state() != QProcess::NotRunning) {
        qWarning() << "[AppProcess]" << m_appId << "- Already running";
        return false;
    }

    m_appPath    = appPath;
    m_entryPoint = entryPoint;

    if (!m_process) {
        m_process = new QProcess(this);

        // Connect signals
        connect(m_process, &QProcess::started, this, &MarathonAppProcess::handleStarted);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                &MarathonAppProcess::handleFinished);
        connect(m_process, &QProcess::errorOccurred, this,
                &MarathonAppProcess::handleErrorOccurred);
        connect(m_process, &QProcess::stateChanged, this, &MarathonAppProcess::handleStateChanged);

        // Forward stdout/stderr to parent process for debugging
        m_process->setProcessChannelMode(QProcess::ForwardedChannels);
    }

    // Build command to run the app
    // For now, we'll run a standalone QML app runner
    // TODO: Create marathon-app-runner executable
    QString     program = QCoreApplication::applicationDirPath() + "/marathon-app-runner";
    QStringList arguments;
    arguments << "--app-id" << m_appId;
    arguments << "--app-path" << appPath;
    arguments << "--entry-point" << entryPoint;

    qInfo() << "[AppProcess]" << m_appId << "- Starting in separate process:";
    qInfo() << "[AppProcess]   Program:" << program;
    qInfo() << "[AppProcess]   Arguments:" << arguments;
    qInfo() << "[AppProcess]   ✅ ISOLATED: App crashes won't affect the shell!";

    m_process->start(program, arguments);

    // Wait a bit to see if it starts
    if (!m_process->waitForStarted(5000)) {
        m_errorString = "Failed to start process: " + m_process->errorString();
        qCritical() << "[AppProcess]" << m_appId << "- " << m_errorString;
        emit errorStringChanged();
        return false;
    }

    return true;
}

void MarathonAppProcess::stop() {
    if (!m_process || m_process->state() == QProcess::NotRunning) {
        return;
    }

    qDebug() << "[AppProcess]" << m_appId << "- Stopping gracefully";
    m_process->terminate();

    // Give it 3 seconds to terminate gracefully
    QTimer::singleShot(3000, this, [this]() {
        if (m_process && m_process->state() != QProcess::NotRunning) {
            qWarning() << "[AppProcess]" << m_appId << "- Didn't stop gracefully, force killing";
            m_process->kill();
        }
    });
}

void MarathonAppProcess::kill() {
    if (!m_process || m_process->state() == QProcess::NotRunning) {
        return;
    }

    qDebug() << "[AppProcess]" << m_appId << "- Force killing";
    m_process->kill();
}

void MarathonAppProcess::restart() {
    qDebug() << "[AppProcess]" << m_appId << "- Restarting";
    stop();

    // Wait a bit before restarting
    QTimer::singleShot(1000, this, [this]() { start(m_appPath, m_entryPoint); });
}

void MarathonAppProcess::handleStarted() {
    qInfo() << "[AppProcess]" << m_appId
            << "- Process started successfully (PID:" << m_process->processId() << ")";
    m_crashCount = 0; // Reset crash count on successful start
    emit runningChanged();
    emit started();
}

void MarathonAppProcess::handleFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    m_exitCode = exitCode;

    qInfo() << "[AppProcess]" << m_appId << "- Process finished";
    qInfo() << "[AppProcess]   Exit code:" << exitCode;
    qInfo() << "[AppProcess]   Exit status:"
            << (exitStatus == QProcess::NormalExit ? "Normal" : "Crashed");

    if (exitStatus == QProcess::CrashExit) {
        m_crashCount++;
        qCritical() << "[AppProcess]" << m_appId << "- CRASHED! (crash count:" << m_crashCount
                    << "/" << MAX_CRASHES << ")";
        qCritical() << "[AppProcess]   ✅ Shell is still running - isolation worked!";

        if (m_crashCount < MAX_CRASHES) {
            qInfo() << "[AppProcess]   Auto-restarting in 2 seconds...";
            QTimer::singleShot(2000, this, &MarathonAppProcess::restart);
        } else {
            qCritical() << "[AppProcess]   Too many crashes, giving up";
            m_errorString = QString("App crashed %1 times, not restarting").arg(m_crashCount);
            emit errorStringChanged();
        }

        emit crashed();
    }

    emit runningChanged();
    emit exitCodeChanged();
    emit finished(exitCode, exitStatus);
}

void MarathonAppProcess::handleErrorOccurred(QProcess::ProcessError error) {
    QString errorStr;
    switch (error) {
        case QProcess::FailedToStart: errorStr = "Failed to start"; break;
        case QProcess::Crashed: errorStr = "Crashed"; break;
        case QProcess::Timedout: errorStr = "Timed out"; break;
        case QProcess::WriteError: errorStr = "Write error"; break;
        case QProcess::ReadError: errorStr = "Read error"; break;
        case QProcess::UnknownError: errorStr = "Unknown error"; break;
    }

    m_errorString = errorStr;
    qCritical() << "[AppProcess]" << m_appId << "- Error:" << errorStr;

    emit errorStringChanged();
    emit errorOccurred(error);
}

void MarathonAppProcess::handleStateChanged(QProcess::ProcessState state) {
    QString stateStr;
    switch (state) {
        case QProcess::NotRunning: stateStr = "Not Running"; break;
        case QProcess::Starting: stateStr = "Starting"; break;
        case QProcess::Running: stateStr = "Running"; break;
    }

    qDebug() << "[AppProcess]" << m_appId << "- State changed:" << stateStr;
}
