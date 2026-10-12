#include "hostedapp.h"

#include "keelhost.h"

#include <QProcessEnvironment>
#include <QTimer>

HostedApp::HostedApp(KeelHost *host, const QString &program, const QStringList &arguments,
                     int closeGraceMs, QObject *parent)
    : QObject(parent)
    , m_host(host)
    , m_program(program)
    , m_arguments(arguments)
    , m_closeGraceMs(closeGraceMs) {
    m_process.setProcessChannelMode(QProcess::ForwardedChannels);
    connect(&m_process, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus) { emit finished(exitCode); });
}

bool HostedApp::start() {
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    const auto          vars = m_host->environment();
    for (auto it = vars.cbegin(); it != vars.cend(); ++it)
        env.insert(it.key(), it.value());
    m_process.setProcessEnvironment(env);
    m_process.start(m_program, m_arguments);
    return m_process.waitForStarted();
}

void HostedApp::close() {
    if (m_closing || m_process.state() == QProcess::NotRunning)
        return;
    m_closing = true;
    m_host->requestClose();
    QTimer::singleShot(m_closeGraceMs, this, [this]() {
        if (m_process.state() == QProcess::NotRunning)
            return;
        m_process.terminate();
        QTimer::singleShot(m_closeGraceMs, this, [this]() {
            if (m_process.state() != QProcess::NotRunning)
                m_process.kill();
        });
    });
}
