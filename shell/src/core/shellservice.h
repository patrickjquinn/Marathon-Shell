// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Peer-to-peer D-Bus server the nested app connects to (address in
// KEEL_SHELL_DBUS and FLATPAK_MALIIT_CONTAINER_DBUS). Every connection gets:
//   /                            org.container               (qt-runner compat, Maliit)
//   /org/shipwright/keel/Shell   org.shipwright.keel.Shell1  (Keel contract)
// See PROTOCOL.md.

#ifndef KEEL_SHELLSERVICE_H
#define KEEL_SHELLSERVICE_H

#include <QDBusAbstractAdaptor>
#include <QObject>
#include <QVariantMap>

class QDBusConnection;
class QDBusServer;

namespace keel {

class ContainerState;
class ShellState;

#define KEEL_SHELL_DBUS_IFACE "org.shipwright.keel.Shell1"
#define KEEL_SHELL_DBUS_PATH "/org/shipwright/keel/Shell"

// The exported object. QDBusAbstractAdaptor needs a parent QObject per
// connection target, so this thin object wraps the shared ShellState.
class KeelShellObject : public QObject
{
    Q_OBJECT
public:
    explicit KeelShellObject(ShellState *state, QObject *parent = nullptr);
    ShellState *state() const { return m_state; }

signals:
    void OrientationChanged(int degrees);
    void ContentOrientationChanged(int degrees);
    void ActiveChanged(bool active);
    void CoverStatusChanged(int status);
    void AmbienceChanged(const QVariantMap &ambience);
    void DpiChanged(int dpi);
    void CloseRequested();

private:
    ShellState *m_state;
};

class KeelShellAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", KEEL_SHELL_DBUS_IFACE)
    Q_PROPERTY(int ProtocolVersion READ protocolVersion)
    Q_PROPERTY(int Orientation READ orientation)
    Q_PROPERTY(int ContentOrientation READ contentOrientation)
    Q_PROPERTY(bool Active READ active)
    Q_PROPERTY(int CoverStatus READ coverStatus)
    Q_PROPERTY(QVariantMap Ambience READ ambience)
    Q_PROPERTY(int Dpi READ dpi)

public:
    explicit KeelShellAdaptor(KeelShellObject *parent);

    int protocolVersion() const { return 1; }
    int orientation() const;
    int contentOrientation() const;
    bool active() const;
    int coverStatus() const;
    QVariantMap ambience() const;
    int dpi() const;

public slots:
    void Activate();
    void SetContentOrientation(int degrees);
    QVariantMap GetAmbience();
    QString Ping();

signals:
    void OrientationChanged(int degrees);
    void ContentOrientationChanged(int degrees);
    void ActiveChanged(bool active);
    void CoverStatusChanged(int status);
    void AmbienceChanged(const QVariantMap &ambience);
    void DpiChanged(int dpi);
    void CloseRequested();

private:
    KeelShellObject *m_object;
};

// Access control (PROTOCOL.md section 4):
// - By default the server listens on a filesystem socket,
//   "unix:path=<dir>/bus", in a fresh 0700 directory under $XDG_RUNTIME_DIR
//   (or the system temp dir without one), so only this uid (and root) can
//   connect() at all. Never an abstract socket, which any process in the
//   network namespace can reach.
// - Anonymous authentication is refused, so libdbus authenticates every peer
//   as a uid (EXTERNAL: the kernel's SO_PEERCRED) and admits only our own
//   uid. QDBusServer offers no hook to check credentials ourselves:
//   newConnection() is emitted on accept(), before authentication.
class ShellService : public QObject
{
    Q_OBJECT
public:
    ShellService(ShellState *state, bool portraitPrimary, QObject *parent = nullptr);
    ~ShellService() override;

    // Empty address: the private filesystem socket described above.
    // Otherwise any QDBusServer address (--bus-address), still without
    // anonymous authentication.
    bool listen(const QString &address = QString());
    QString address() const;
    // The private socket's directory; empty with an explicit address.
    QString socketDirectory() const { return m_socketDir; }
    // Connections accepted so far. libdbus counts a peer here before it has
    // authenticated; one that fails is dropped before any call reaches us.
    int connectionCount() const { return m_connections; }

signals:
    void clientConnected();

private slots:
    void onNewConnection(const QDBusConnection &connection);

private:
    void removeSocketDirectory();

    ShellState *m_state;
    ContainerState *m_container;
    KeelShellObject *m_keel;
    QDBusServer *m_server = nullptr;
    QString m_socketDir;
    int m_connections = 0;
};

} // namespace keel

#endif // KEEL_SHELLSERVICE_H
