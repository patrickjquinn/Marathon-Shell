#include "hostedapp.h"

#include "keelhost.h"

#include <QFile>
#include <QProcessEnvironment>
#include <QTimer>

// The shell freezes a backgrounded app's cgroup (marathon-app-<id>); a
// frozen app never reads CloseRequested. A sandboxed app sits below bwrap.
static void thawAppCgroup(qint64 pid, int depth = 0) {
    QFile cgroup(QStringLiteral("/proc/%1/cgroup").arg(pid));
    if (!cgroup.open(QIODevice::ReadOnly))
        return;
    const QString path = QString::fromUtf8(cgroup.readLine().trimmed());
    if (path.startsWith(QLatin1String("0::")) &&
        path.section(QLatin1Char('/'), -1).startsWith(QLatin1String("marathon-app-"))) {
        QFile freeze(QStringLiteral("/sys/fs/cgroup") + path.mid(3) +
                     QStringLiteral("/cgroup.freeze"));
        if (freeze.open(QIODevice::WriteOnly))
            freeze.write("0");
        return;
    }
    QFile children(QStringLiteral("/proc/%1/task/%1/children").arg(pid));
    if (depth < 3 && children.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> pids = children.readAll().split(' ');
        for (const QByteArray &child : pids) {
            if (child.trimmed().toLongLong() > 0)
                thawAppCgroup(child.trimmed().toLongLong(), depth + 1);
        }
    }
}

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
    thawAppCgroup(m_process.processId());
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
