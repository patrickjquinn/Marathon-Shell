// marathon-keel-host --app-id ID [--dpi N] [--sailjail P1,P2 --org ORG --app APP]
//                    -- PROGRAM [ARGS...]
//
// Runs a native Keel app (a Sailfish app rebuilt on Keel's sailfishapp) under
// a Keel host, as marathon-app-runner does for QML apps.

#include "ambienceclient.h"
#include "hostedapp.h"
#include "keelhost.h"
#include "sailjail.h"

#include <QDir>
#include <QStandardPaths>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QSocketNotifier>

#include <csignal>
#include <sys/socket.h>
#include <unistd.h>

static int g_termFds[2] = {-1, -1};

static void onTerm(int) {
    const char c = 1;
    (void)::write(g_termFds[0], &c, 1);
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    QStringList      args = app.arguments().mid(1);
    const qsizetype  sep  = args.indexOf(QStringLiteral("--"));
    if (sep < 0 || sep + 1 >= args.size()) {
        qCritical("usage: marathon-keel-host --app-id ID [--dpi N] -- PROGRAM [ARGS...]");
        return 2;
    }
    const QStringList options = args.mid(0, sep);
    const QStringList command = args.mid(sep + 1);
    const auto        option  = [&options](const QString &name) {
        const qsizetype i = options.indexOf(name);
        return i >= 0 && i + 1 < options.size() ? options.at(i + 1) : QString();
    };
    const QString appId = option(QStringLiteral("--app-id"));
    const int     dpi   = option(QStringLiteral("--dpi")).toInt();

    AmbienceClient ambience;
    ambience.fetchNow(1000);
    KeelHost host(dpi > 0 ? dpi : 160);
    host.setAmbience(ambience.ambience());
    if (!host.start(qEnvironmentVariable("XDG_RUNTIME_DIR"))) {
        qCritical("marathon-keel-host: cannot start the Keel host");
        return 1;
    }
    QObject::connect(&ambience, &AmbienceClient::ambienceChanged, &host, &KeelHost::setAmbience);
    host.onActivate = [appId]() {
        QDBusMessage call = QDBusMessage::createMethodCall(
            QStringLiteral("org.marathonos.Shell"), QStringLiteral("/org/marathonos/Shell/Navigation"),
            QStringLiteral("org.marathonos.Shell.Navigation1"), QStringLiteral("LaunchApp"));
        call << appId;
        QDBusConnection::sessionBus().asyncCall(call);
    };

    // A Sailfish app with Sailjail permissions runs in a sandbox built from them.
    QString     program   = command.first();
    QStringList arguments = command.mid(1);
    const QString bwrap   = QStandardPaths::findExecutable(QStringLiteral("bwrap"));
    if (options.contains(QStringLiteral("--sailjail")) && !bwrap.isEmpty()) {
        const QString org  = option(QStringLiteral("--org"));
        const QString name = option(QStringLiteral("--app"));
        const QString home = QDir::homePath();
        for (const char *base : {"/.local/share/", "/.cache/", "/.config/"})
            QDir().mkpath(home + QLatin1String(base) + org + QLatin1Char('/') + name);
        arguments = Sailjail::bwrapArgs(option(QStringLiteral("--sailjail")).split(QLatin1Char(','), Qt::SkipEmptyParts),
                                        org, name, home, qEnvironmentVariable("XDG_RUNTIME_DIR"))
                    << QStringLiteral("--") << program << arguments;
        program = bwrap;
    }

    HostedApp hosted(&host, program, arguments);
    QObject::connect(&hosted, &HostedApp::finished, &app, [&app](int code) { app.exit(code); });
    if (!hosted.start()) {
        qCritical("marathon-keel-host: cannot start %s", qPrintable(program));
        return 1;
    }

    if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, g_termFds) == 0) {
        auto *notifier = new QSocketNotifier(g_termFds[1], QSocketNotifier::Read, &app);
        QObject::connect(notifier, &QSocketNotifier::activated, &hosted, [&hosted]() {
            char c;
            (void)::read(g_termFds[1], &c, 1);
            hosted.close();
        });
        struct sigaction sa {};
        sa.sa_handler = onTerm;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_RESTART;
        ::sigaction(SIGTERM, &sa, nullptr);
    }
    return app.exec();
}
