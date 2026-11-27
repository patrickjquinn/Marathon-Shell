#include "homeunlock.h"

#include <QGuiApplication>
#include <QQuickWindow>
#include <QtDebug>
#include <qpa/qplatformnativeinterface.h>
#include <cstdio>
#include <xf86drm.h>

HomeUnlock::HomeUnlock(const QStringList &command, QObject *parent)
    : QObject(parent)
    , m_command(command) {
    m_process.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    connect(&m_process, &QProcess::stateChanged, this, &HomeUnlock::busyChanged);
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        if (status == QProcess::NormalExit && code == 0)
            emit opened();
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

// After the frame on screen now, which is the splash's.
void HomeUnlock::release() {
    auto *window = qobject_cast<QQuickWindow *>(QGuiApplication::topLevelWindows().value(0));
    connect(window, &QQuickWindow::frameSwapped, this, &HomeUnlock::dropMaster,
            static_cast<Qt::ConnectionType>(Qt::QueuedConnection | Qt::SingleShotConnection));
    window->update();
}

void HomeUnlock::dropMaster() {
    void *fd = QGuiApplication::platformNativeInterface()->nativeResourceForIntegration(
        QByteArrayLiteral("dri_fd"));
    if (!fd || drmDropMaster(static_cast<int>(reinterpret_cast<qintptr>(fd))) != 0)
        qWarning() << "[HomeUnlock] cannot give up DRM master";
    std::fputs("open\n", stdout);
    std::fflush(stdout);
}
