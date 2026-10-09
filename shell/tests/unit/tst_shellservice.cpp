// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Talks to ShellService over a real peer-to-peer D-Bus connection, the way
// the nested app (Keel) and the Maliit input context plugin do.

#include <QtTest>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusVariant>
#include <QFileInfo>
#include <QLocalSocket>
#include <QTemporaryDir>

#include <cerrno>
#include <csignal>
#include <grp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include "core/shellservice.h"
#include "core/shellstate.h"

using namespace keel;

class SignalSink : public QObject
{
    Q_OBJECT
public:
    QList<int> orientations;
    QList<int> containerOrientations;
    QList<QVariantMap> ambiences;
    int closeRequests = 0;
public slots:
    void onOrientation(int d) { orientations << d; }
    void onContainerOrientation(int d) { containerOrientations << d; }
    void onAmbience(const QVariantMap &m) { ambiences << m; }
    void onClose() { ++closeRequests; }
};

// Server and client live in the same thread here, so every call must be
// asynchronous (a blocking call would starve the server side).
static QDBusMessage waitFor(const QDBusPendingCall &call)
{
    const QDBusPendingCall &c = call;
    QElapsedTimer t;
    t.start();
    while (!c.isFinished() && t.elapsed() < 5000)
        QTest::qWait(5);
    return c.reply();
}

static QVariant getProp(const QDBusConnection &c, const QString &path, const QString &iface,
                        const QString &name)
{
    QDBusMessage m = QDBusMessage::createMethodCall(QString(), path,
                                                    QStringLiteral("org.freedesktop.DBus.Properties"),
                                                    QStringLiteral("Get"));
    m << iface << name;
    const QDBusMessage r = waitFor(c.asyncCall(m));
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
        return QVariant();
    return r.arguments().first().value<QDBusVariant>().variant();
}

static QDBusMessage callMethod(const QDBusConnection &c, const QString &path, const QString &iface,
                               const QString &method, const QVariantList &args = QVariantList())
{
    QDBusMessage m = QDBusMessage::createMethodCall(QString(), path, iface, method);
    m.setArguments(args);
    return waitFor(c.asyncCall(m));
}

static const QString kPath = QStringLiteral(KEEL_SHELL_DBUS_PATH);
static const QString kIface = QStringLiteral(KEEL_SHELL_DBUS_IFACE);
static const QString cPath = QStringLiteral("/");
static const QString cIface = QStringLiteral("org.container");

// The socket path inside a "unix:path=..." address.
static QString socketPath(const QString &address)
{
    const QString prefix = QStringLiteral("unix:path=");
    if (!address.startsWith(prefix))
        return QString();
    return address.mid(prefix.size()).section(QLatin1Char(','), 0, 0);
}

// A D-Bus method call, little-endian, serial 1: Activate() on the Keel
// object (path, interface and member header fields, no body).
static QByteArray rawActivateMessage()
{
    static const char bytes[] =
        "l\x01\x00\x01\x00\x00\x00\x00\x01\x00\x00\x00\x61\x00\x00\x00"
        "\x01\x01o\x00\x1a\x00\x00\x00/org/shipwright/keel/Shell\x00\x00\x00\x00\x00\x00"
        "\x02\x01s\x00\x1a\x00\x00\x00org.shipwright.keel.Shell1\x00\x00\x00\x00\x00\x00"
        "\x03\x01s\x00\x08\x00\x00\x00Activate\x00\x00\x00\x00\x00\x00\x00\x00";
    return QByteArray(bytes, sizeof bytes - 1);
}

// Forks a child that switches to uid/gid 65534 and connects to `path`.
// Without `authenticate`, it expects connect() to fail with EACCES. With it,
// it expects to connect, pass SASL EXTERNAL as itself and then be dropped
// when it starts the session. Returns 0 when the child saw what it expected.
// The parent keeps its event loop running (QtDBus authenticates there).
static int runAsNobody(const QString &path, bool authenticate)
{
    const QByteArray p = QFile::encodeName(path);
    const pid_t pid = ::fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        // Child: async-signal-safe calls only.
        if (::setgroups(0, nullptr) != 0 || ::setgid(65534) != 0 || ::setuid(65534) != 0)
            ::_exit(2);
        const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
        sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        if (fd < 0 || static_cast<size_t>(p.size()) >= sizeof addr.sun_path)
            ::_exit(3);
        memcpy(addr.sun_path, p.constData(), static_cast<size_t>(p.size()));
        const int rc = ::connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr);
        if (!authenticate)
            ::_exit(rc != 0 && errno == EACCES ? 0 : 4);
        if (rc != 0)
            ::_exit(5);
        // "65534" in hex.
        static const char auth[] = "\0AUTH EXTERNAL 3635353334\r\nBEGIN\r\n";
        if (::write(fd, auth, sizeof auth - 1) != static_cast<ssize_t>(sizeof auth - 1))
            ::_exit(6);
        // Read until the server closes the connection; never get further.
        char buf[256];
        pollfd pfd{ fd, POLLIN, 0 };
        for (;;) {
            if (::poll(&pfd, 1, 5000) <= 0)
                ::_exit(7);   // still connected after 5 s
            const ssize_t n = ::read(fd, buf, sizeof buf);
            if (n == 0 || (n < 0 && errno == ECONNRESET))
                ::_exit(0);
            if (n < 0)
                ::_exit(8);
        }
    }
    int status = 0;
    QElapsedTimer t;
    t.start();
    while (::waitpid(pid, &status, WNOHANG) == 0) {
        if (t.elapsed() > 15000) {
            ::kill(pid, SIGKILL);
            ::waitpid(pid, &status, 0);
            return -2;
        }
        QTest::qWait(20);
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -3;
}

class TestShellService : public QObject
{
    Q_OBJECT
private:
    QTemporaryDir m_runtime;

    QDBusConnection connect(ShellService &service, const QString &name)
    {
        QDBusConnection c = QDBusConnection::connectToPeer(service.address(), name);
        // The server registers objects when it sees the connection.
        QElapsedTimer t;
        t.start();
        while (service.connectionCount() == 0 && t.elapsed() < 5000)
            QTest::qWait(10);
        return c;
    }

private slots:
    void initTestCase()
    {
        // A private, short XDG_RUNTIME_DIR (socket paths are limited to 108
        // bytes), as the session provides one on the device.
        QVERIFY(m_runtime.isValid());
        QFile::setPermissions(m_runtime.path(),
                              QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        qputenv("XDG_RUNTIME_DIR", QFile::encodeName(m_runtime.path()));
    }

    void privateSocket()
    {
        ShellState state;
        QString dir;
        QString path;
        {
            ShellService service(&state, true);
            QVERIFY(service.listen());
            // A filesystem socket, never an abstract one, in a fresh
            // directory under XDG_RUNTIME_DIR that only we can enter.
            path = socketPath(service.address());
            QVERIFY2(!path.isEmpty(), qPrintable(service.address()));
            dir = service.socketDirectory();
            QCOMPARE(QFileInfo(path).absolutePath(), dir);
            QCOMPARE(QFileInfo(dir).absolutePath(), QFileInfo(m_runtime.path()).absoluteFilePath());
            QCOMPARE(QFileInfo(dir).permissions() & (QFile::ReadGroup | QFile::WriteGroup
                                                     | QFile::ExeGroup | QFile::ReadOther
                                                     | QFile::WriteOther | QFile::ExeOther),
                     QFileDevice::Permissions());
            QCOMPARE(QFileInfo(dir).ownerId(), uint(::geteuid()));
            QVERIFY(QFileInfo::exists(path));

            // Two shells never share a socket.
            ShellService other(&state, true);
            QVERIFY(other.listen());
            QVERIFY(other.socketDirectory() != dir);
        }
        // Removed with the service.
        QVERIFY(!QFileInfo::exists(path));
        QVERIFY(!QFileInfo::exists(dir));
    }

    void sameUidIsAccepted()
    {
        ShellState state;
        ShellService service(&state, true);
        QVERIFY(service.listen());
        QDBusConnection c = connect(service, QStringLiteral("keel-test-uid"));
        QVERIFY(c.isConnected());
        QCOMPARE(service.connectionCount(), 1);
        // libdbus authenticated the peer as our uid (EXTERNAL), so calls work.
        const QDBusMessage ping = callMethod(c, kPath, kIface, QStringLiteral("Ping"));
        QCOMPARE(ping.arguments().value(0).toString(), QStringLiteral("keel-shell"));
        QDBusConnection::disconnectFromPeer(QStringLiteral("keel-test-uid"));
    }

    void anonymousIsRefused()
    {
        ShellState state;
        ShellService service(&state, true);
        QVERIFY(service.listen());
        QSignalSpy activate(&state, &ShellState::activateRequested);
        QLocalSocket socket;
        socket.connectToServer(socketPath(service.address()));
        QVERIFY(socket.waitForConnected(5000));
        // D-Bus SASL: a NUL byte, then AUTH with the ANONYMOUS mechanism.
        static const char auth[] = "\0AUTH ANONYMOUS 6b65656c\r\n";
        socket.write(auth, sizeof auth - 1);
        QTRY_VERIFY_WITH_TIMEOUT(socket.canReadLine()
                                 || socket.state() == QLocalSocket::UnconnectedState, 5000);
        const QByteArray reply = socket.readLine();
        if (reply.startsWith("OK")) {
            // libdbus completes the SASL exchange, then refuses the
            // anonymous identity when the client starts the session.
            socket.write("BEGIN\r\n");
            socket.write(rawActivateMessage());
            QTRY_COMPARE_WITH_TIMEOUT(socket.state(), QLocalSocket::UnconnectedState, 5000);
        } else {
            QVERIFY2(reply.startsWith("REJECTED"), reply.constData());
        }
        // The call never reached keel-shell.
        QCoreApplication::processEvents();
        QCOMPARE(activate.count(), 0);
    }

    void otherUidIsRefused()
    {
        if (::geteuid() != 0)
            QSKIP("needs root to switch to another uid");
        ShellState state;
        ShellService service(&state, true);
        QVERIFY(service.listen());
        // The private directory keeps other users from even connecting.
        QCOMPARE(runAsNobody(socketPath(service.address()), false), 0);
    }

    void otherUidFailsAuthentication()
    {
        // With an explicit --bus-address whose socket other users can reach,
        // libdbus still admits only our uid.
        if (::geteuid() != 0)
            QSKIP("needs root to switch to another uid");
        QTemporaryDir open(QStringLiteral("/tmp/keel-open-XXXXXX"));
        QVERIFY(open.isValid());
        QFile::setPermissions(open.path(), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner
                                           | QFile::ReadOther | QFile::WriteOther | QFile::ExeOther);
        ShellState state;
        QSignalSpy activate(&state, &ShellState::activateRequested);
        ShellService service(&state, true);
        QVERIFY(service.listen(QStringLiteral("unix:path=") + open.path() + QStringLiteral("/bus")));
        ::chmod(QFile::encodeName(open.path() + QStringLiteral("/bus")).constData(), 0666);
        QCOMPARE(runAsNobody(socketPath(service.address()), true), 0);
        QCoreApplication::processEvents();
        QCOMPARE(activate.count(), 0);
    }

    void keelInterface()
    {
        ShellState state;
        state.setDpi(458);
        state.setOrientation(90);
        QVariantMap amb;
        amb.insert(QStringLiteral("/desktop/jolla/theme/color/highlight"), QStringLiteral("#ff8080"));
        state.setAmbience(amb);

        ShellService service(&state, true);
        QVERIFY(service.listen());
        QVERIFY(!service.address().isEmpty());
        QDBusConnection c = connect(service, QStringLiteral("keel-test-1"));
        QVERIFY(c.isConnected());

        QCOMPARE(getProp(c, kPath, kIface, QStringLiteral("ProtocolVersion")).toInt(), 1);
        QCOMPARE(getProp(c, kPath, kIface, QStringLiteral("Dpi")).toInt(), 458);
        QCOMPARE(getProp(c, kPath, kIface, QStringLiteral("Orientation")).toInt(), 90);
        QCOMPARE(getProp(c, kPath, kIface, QStringLiteral("Active")).toBool(), false);

        const QDBusMessage ping = callMethod(c, kPath, kIface, QStringLiteral("Ping"));
        QCOMPARE(ping.arguments().value(0).toString(), QStringLiteral("keel-shell"));

        const QDBusMessage ambReply = callMethod(c, kPath, kIface, QStringLiteral("GetAmbience"));
        QCOMPARE(ambReply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(qdbus_cast<QVariantMap>(ambReply.arguments().value(0)).value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString(),
                 QStringLiteral("#ff8080"));

        SignalSink sink;
        QVERIFY(c.connect(QString(), QStringLiteral(KEEL_SHELL_DBUS_PATH),
                          QStringLiteral(KEEL_SHELL_DBUS_IFACE), QStringLiteral("OrientationChanged"),
                          &sink, SLOT(onOrientation(int))));
        QVERIFY(c.connect(QString(), QStringLiteral(KEEL_SHELL_DBUS_PATH),
                          QStringLiteral(KEEL_SHELL_DBUS_IFACE), QStringLiteral("AmbienceChanged"),
                          &sink, SLOT(onAmbience(QVariantMap))));
        QVERIFY(c.connect(QString(), QStringLiteral(KEEL_SHELL_DBUS_PATH),
                          QStringLiteral(KEEL_SHELL_DBUS_IFACE), QStringLiteral("CloseRequested"),
                          &sink, SLOT(onClose())));
        state.setOrientation(270);
        amb.insert(QStringLiteral("/desktop/jolla/theme/color_scheme"), QStringLiteral("darkonlight"));
        state.setAmbience(amb);
        state.requestClose();
        QTRY_COMPARE_WITH_TIMEOUT(sink.orientations, QList<int>() << 270, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(sink.ambiences.size(), 1, 5000);
        QCOMPARE(sink.ambiences.first().value(QStringLiteral("/desktop/jolla/theme/color_scheme")).toString(),
                 QStringLiteral("darkonlight"));
        QTRY_COMPARE_WITH_TIMEOUT(sink.closeRequests, 1, 5000);

        // App -> shell requests.
        QSignalSpy activate(&state, &ShellState::activateRequested);
        callMethod(c, kPath, kIface, QStringLiteral("Activate"));
        QTRY_COMPARE_WITH_TIMEOUT(activate.count(), 1, 5000);
        callMethod(c, kPath, kIface, QStringLiteral("SetContentOrientation"), QVariantList() << 90);
        QTRY_COMPARE_WITH_TIMEOUT(state.contentOrientation(), 90, 5000);
        QCOMPARE(getProp(c, kPath, kIface, QStringLiteral("ContentOrientation")).toInt(), 90);

        QDBusConnection::disconnectFromPeer(QStringLiteral("keel-test-1"));
    }

    void qtRunnerContainerInterface()
    {
        // What the Qt6 Maliit input context plugin does
        // (maliit-framework input-context/minputcontext.cpp).
        ShellState state;
        ShellService service(&state, true);
        QVERIFY(service.listen());
        QDBusConnection c = connect(service, QStringLiteral("flatpak_container"));
        QCOMPARE(getProp(c, cPath, cIface, QStringLiteral("activeState")).toInt(), 0);
        QCOMPARE(getProp(c, cPath, cIface, QStringLiteral("orientation")).toInt(), 0);

        SignalSink sink;
        QVERIFY(c.connect(QString(), QStringLiteral("/"), QStringLiteral("org.container"),
                          QStringLiteral("orientationChanged"), &sink,
                          SLOT(onContainerOrientation(int))));
        state.setActive(true);
        QTRY_COMPARE_WITH_TIMEOUT(getProp(c, cPath, cIface, QStringLiteral("activeState")).toInt(), 1, 5000);

        // Content orientation 90 deg from portrait = Qt::InvertedLandscape;
        // Maliit's table gives 270 for that (qt-runner behaviour).
        state.setContentOrientation(90);
        QTRY_COMPARE_WITH_TIMEOUT(sink.containerOrientations, QList<int>() << 270, 5000);
        QCOMPARE(getProp(c, cPath, cIface, QStringLiteral("orientation")).toInt(), 270);

        callMethod(c, cPath, cIface, QStringLiteral("keyboardRect"),
                   QVariantList() << true << 0 << 1400 << 1080 << 600);
        QTRY_COMPARE_WITH_TIMEOUT(state.keyboardActive(), true, 5000);
        QCOMPARE(state.keyboardRect(), QRect(0, 1400, 1080, 600));
        callMethod(c, cPath, cIface, QStringLiteral("keyboardRect"),
                   QVariantList() << false << 0 << 0 << 0 << 0);
        QTRY_COMPARE_WITH_TIMEOUT(state.keyboardActive(), false, 5000);

        // Nothing else on the object is callable.
        const QDBusMessage other = callMethod(c, cPath, cIface,
                                              QStringLiteral("onContentOrientationChanged"),
                                              QVariantList() << 0);
        QCOMPARE(other.type(), QDBusMessage::ErrorMessage);

        QDBusConnection::disconnectFromPeer(QStringLiteral("flatpak_container"));
    }
};

QTEST_GUILESS_MAIN(TestShellService)
#include "tst_shellservice.moc"
