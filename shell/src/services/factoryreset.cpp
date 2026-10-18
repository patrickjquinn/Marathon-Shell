#include "factoryreset.h"

#include <QFileInfo>
#include <QLocalSocket>

#include <utility>

#include "securitymanager.h"

FactoryReset::FactoryReset(SecurityManager *security, QString socketPath, QObject *parent)
    : QObject(parent)
    , m_security(security)
    , m_socketPath(std::move(socketPath)) {}

bool FactoryReset::supported() const {
    return QFileInfo::exists(m_socketPath);
}

void FactoryReset::erase(const QString &secret) {
    if (!supported()) {
        emit failed(QStringLiteral("This device can't erase itself"));
        return;
    }
    if (const QString refusal = m_security->confirmOwner(secret); !refusal.isEmpty()) {
        emit failed(refusal);
        return;
    }

    auto *socket = new QLocalSocket(this);
    // The service answers "ok", or why not, and closes; the device restarts after an ok.
    auto finish = [this, socket] {
        if (socket->property("finished").toBool())
            return;
        socket->setProperty("finished", true);
        const QByteArray reply = socket->readAll().trimmed();
        socket->deleteLater();
        if (reply == "ok")
            return;
        emit failed(reply.isEmpty()
                        ? QStringLiteral("Couldn't reach the erase service: %1").arg(socket->errorString())
                        : QString::fromUtf8(reply));
    };
    connect(socket, &QLocalSocket::connected, socket, [socket] { socket->write("erase\n"); });
    connect(socket, &QLocalSocket::disconnected, this, finish);
    connect(socket, &QLocalSocket::errorOccurred, this, finish);
    socket->connectToServer(m_socketPath);
}
