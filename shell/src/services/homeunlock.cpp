#include "homeunlock.h"

#include <QCoreApplication>

HomeUnlock::HomeUnlock(const QStringList &command, QObject *parent)
    : QObject(parent)
    , m_command(command) {
    m_process.setProcessChannelMode(QProcess::ForwardedChannels);
    connect(&m_process, &QProcess::stateChanged, this, &HomeUnlock::busyChanged);
    connect(&m_process, &QProcess::finished, this,
            [this](int code, QProcess::ExitStatus status) {
                if (status == QProcess::NormalExit && code == 0)
                    QCoreApplication::quit();
                else
                    emit rejected();
            });
}

void HomeUnlock::submit(const QString &pin) {
    if (busy())
        return;
    m_process.start(m_command.first(), m_command.mid(1));
    m_process.write(pin.toUtf8() + '\n');
    m_process.closeWriteChannel();
}
