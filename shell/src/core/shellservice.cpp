// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "shellservice.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMetaType>
#include <QDBusServer>
#include <QDir>
#include <QFile>
#include <QStandardPaths>

#include <cerrno>
#include <cstdlib>
#include <cstring>

#include "containerstate.h"
#include "logging.h"
#include "shellstate.h"

namespace keel {

KeelShellObject::KeelShellObject(ShellState *state, QObject *parent)
    : QObject(parent)
    , m_state(state)
{
    connect(state, &ShellState::orientationChanged, this, &KeelShellObject::OrientationChanged);
    connect(state, &ShellState::contentOrientationChanged,
            this, &KeelShellObject::ContentOrientationChanged);
    connect(state, &ShellState::activeChanged, this, &KeelShellObject::ActiveChanged);
    connect(state, &ShellState::coverStatusChanged, this, &KeelShellObject::CoverStatusChanged);
    connect(state, &ShellState::ambienceChanged, this, &KeelShellObject::AmbienceChanged);
    connect(state, &ShellState::dpiChanged, this, &KeelShellObject::DpiChanged);
    connect(state, &ShellState::closeRequested, this, &KeelShellObject::CloseRequested);
}

KeelShellAdaptor::KeelShellAdaptor(KeelShellObject *parent)
    : QDBusAbstractAdaptor(parent)
    , m_object(parent)
{
    setAutoRelaySignals(true);
}

int KeelShellAdaptor::orientation() const { return m_object->state()->orientation(); }
int KeelShellAdaptor::contentOrientation() const { return m_object->state()->contentOrientation(); }
bool KeelShellAdaptor::active() const { return m_object->state()->active(); }
int KeelShellAdaptor::coverStatus() const { return m_object->state()->coverStatus(); }
QVariantMap KeelShellAdaptor::ambience() const { return m_object->state()->ambience(); }
int KeelShellAdaptor::dpi() const { return m_object->state()->dpi(); }

void KeelShellAdaptor::Activate()
{
    m_object->state()->requestActivate();
}

void KeelShellAdaptor::SetContentOrientation(int degrees)
{
    m_object->state()->setContentOrientation(degrees);
}

QVariantMap KeelShellAdaptor::GetAmbience()
{
    return m_object->state()->ambience();
}

QString KeelShellAdaptor::Ping()
{
    return QStringLiteral("keel-shell");
}

ShellService::ShellService(ShellState *state, bool portraitPrimary, QObject *parent)
    : QObject(parent)
    , m_state(state)
    , m_container(new ContainerState(state, portraitPrimary, this))
    , m_keel(new KeelShellObject(state, this))
{
    new KeelShellAdaptor(m_keel);
}

ShellService::~ShellService()
{
    delete m_server;   // closes the listening socket first
    m_server = nullptr;
    removeSocketDirectory();
}

// A fresh 0700 directory (mkdtemp) for the private socket.
static QString makePrivateDirectory()
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (base.isEmpty() || !QDir(base).exists())
        base = QDir::tempPath();
    QByteArray pattern = QFile::encodeName(base + QStringLiteral("/keel-shell-XXXXXX"));
    if (!::mkdtemp(pattern.data())) {
        qCWarning(lcKeelShell) << "cannot create a private directory in" << base << ":"
                               << std::strerror(errno);
        return QString();
    }
    return QFile::decodeName(pattern);
}

bool ShellService::listen(const QString &address)
{
    QString addr = address;
    if (addr.isEmpty()) {
        m_socketDir = makePrivateDirectory();
        if (m_socketDir.isEmpty())
            return false;
        addr = QStringLiteral("unix:path=") + m_socketDir + QStringLiteral("/bus");
    }
    m_server = new QDBusServer(addr, this);
    if (!m_server->isConnected()) {
        qCWarning(lcKeelShell) << "cannot start the peer D-Bus server on" << addr << ":"
                               << m_server->lastError().message();
        return false;
    }
    // Explicit, although it is QDBusServer's default: libdbus then admits
    // only peers that authenticate as our own uid.
    m_server->setAnonymousAuthenticationAllowed(false);
    connect(m_server, &QDBusServer::newConnection, this, &ShellService::onNewConnection);
    return true;
}

void ShellService::removeSocketDirectory()
{
    if (m_socketDir.isEmpty())
        return;
    // libdbus unlinks a unix:path socket when the server closes; this also
    // covers a server that failed to start.
    QFile::remove(m_socketDir + QStringLiteral("/bus"));
    QDir().rmdir(m_socketDir);
    m_socketDir.clear();
}

QString ShellService::address() const
{
    return m_server ? m_server->address() : QString();
}

void ShellService::onNewConnection(const QDBusConnection &c)
{
    QDBusConnection connection(c);
    // qt-runner compatible object for the Maliit input context plugin. Only
    // the scriptable keyboardRect slot is callable.
    connection.registerObject(QStringLiteral("/"), m_container,
                              QDBusConnection::ExportAllProperties
                              | QDBusConnection::ExportAllSignals
                              | QDBusConnection::ExportScriptableSlots);
    // No registerService(): a peer-to-peer connection has no bus daemon, so
    // there are no names to own. Peers address objects with an empty
    // service (qt-runner registered FLATPAK_RUNNER_DBUS_CONT_SERVICE here;
    // it had no effect).
    // Keel contract.
    connection.registerObject(QStringLiteral(KEEL_SHELL_DBUS_PATH), m_keel,
                              QDBusConnection::ExportAdaptors);
    ++m_connections;
    emit clientConnected();
}

} // namespace keel
