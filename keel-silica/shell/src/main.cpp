// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel-shell entry point. Command line handling follows qt-runner's
// main.cpp (options first, then the program and its arguments), rewritten.

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QScreen>
#include <QStandardPaths>
#include <QTimer>

#include <cmath>
#include <iostream>
#include <utility>
#include <unistd.h>

#include "core/ambience.h"
#include "core/backend.h"
#include "core/launchconfig.h"
#include "core/logging.h"
#include "core/runner.h"
#include "core/shellservice.h"
#include "core/shellstate.h"
#include "core/unixsignals.h"

#if defined(KEEL_BACKEND_QT56)
#include "backend/qt56/backend56.h"
using SelectedBackend = keel::Backend56;
#elif defined(KEEL_BACKEND_QT515)
#include "backend/qt515/backend515.h"
using SelectedBackend = keel::Backend515;
#else
#error "Define KEEL_BACKEND_QT56 or KEEL_BACKEND_QT515"
#endif

#ifndef KEEL_SHELL_VERSION
#define KEEL_SHELL_VERSION "0.1.0"
#endif

namespace {

// When the close comes as SIGTERM from Lipstick, the app gets at most this
// long to act on CloseRequested before keel-shell passes the SIGTERM on.
constexpr int kSigtermGraceMs = 1000;

// Optional diagnostics for tests: KEEL_SHELL_REPORT=/path/file.json is
// rewritten whenever an outer window is shown or hidden.
class Reporter : public QObject
{
    Q_OBJECT
public:
    Reporter(keel::Backend *backend, QString path)
        : m_backend(backend), m_path(std::move(path))
    {
        connect(backend, &keel::Backend::outerWindowShown, this, [this]() { write(); });
        connect(backend, &keel::Backend::outerWindowHidden, this, [this]() { write(); });
    }

    void write()
    {
        QJsonArray windows;
        for (int id : m_backend->outerWindowIds()) {
            QWindow *w = m_backend->outerWindow(id);
            if (!w)
                continue;
            QJsonObject o;
            o.insert(QStringLiteral("id"), id);
            o.insert(QStringLiteral("role"), w->property("keelRole").toString());
            o.insert(QStringLiteral("category"), w->property("CATEGORY").toString());
            o.insert(QStringLiteral("title"), w->title());
            o.insert(QStringLiteral("visible"), w->isVisible());
            o.insert(QStringLiteral("platformWindow"), w->handle() != nullptr);
            windows.append(o);
        }
        QJsonObject root;
        root.insert(QStringLiteral("backend"), m_backend->name());
        root.insert(QStringLiteral("socket"), m_backend->socketName());
        root.insert(QStringLiteral("windows"), windows);
        QSaveFile f(m_path);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(QJsonDocument(root).toJson());
            f.commit();
        }
    }

private:
    keel::Backend *m_backend;
    QString m_path;
};

} // namespace

int main(int argc, char *argv[])
{
    // Parse our command line before QGuiApplication strips Qt options that
    // belong to the nested app (e.g. "-style").
    QStringList rawArgs;
    for (int i = 1; i < argc; ++i)
        rawArgs << QString::fromLocal8Bit(argv[i]);
    const keel::LaunchOptions opts = keel::LaunchConfig::parse(rawArgs);

    if (opts.help) {
        std::cout << keel::LaunchConfig::usage(QString::fromLocal8Bit(argv[0])).toStdString();
        return 0;
    }
    if (opts.version) {
        std::cout << "keel-shell " KEEL_SHELL_VERSION "\n";
        return 0;
    }
    if (!opts.error.isEmpty()) {
        std::cerr << "keel-shell: " << opts.error.toStdString() << "\n"
                  << keel::LaunchConfig::usage(QString::fromLocal8Bit(argv[0])).toStdString();
        return 2;
    }

    // Lipstick-facing windows never have decorations (the Sailfish Qt 5.6
    // client does not draw any; a stock Qt 5.15 client would).
    if (!qEnvironmentVariableIsSet("QT_WAYLAND_DISABLE_WINDOWDECORATION"))
        qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");

    // Keep only argv[0] for Qt so nothing of the app's command line is eaten.
    int qtArgc = 1;
    QGuiApplication app(qtArgc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("keel-shell"));
    QGuiApplication::setOrganizationName(QStringLiteral("shipwright"));
    QGuiApplication::setApplicationVersion(QStringLiteral(KEEL_SHELL_VERSION));
    QGuiApplication::setQuitOnLastWindowClosed(false);
    if (!qEnvironmentVariableIsSet("QT_MESSAGE_PATTERN"))
        qSetMessagePattern(QStringLiteral("keel-shell: %{if-warning}warning: %{endif}"
                                          "%{if-critical}error: %{endif}%{message}"));
    if (opts.verbose || qEnvironmentVariableIsSet("KEEL_SHELL_VERBOSE"))
        keel::enableVerboseLogging();

    keel::ShellState state;
    keel::UnixSignals unixSignals;
    if (!unixSignals.isValid()) {
        // Without the handlers, Lipstick's SIGTERM would kill keel-shell and
        // orphan the app without CloseRequested.
        qCCritical(keel::lcKeelShell).noquote()
                << "cannot install signal handlers:" << unixSignals.errorString();
        return 1;
    }

    // DPI: like qt-runner, the physical DPI of the primary screen unless given.
    int dpi = opts.dpi;
    if (dpi <= 0 && QGuiApplication::primaryScreen())
        dpi = static_cast<int>(std::lround(QGuiApplication::primaryScreen()->physicalDotsPerInch()));
    state.setDpi(dpi);

    // Ambience.
    QScopedPointer<keel::AmbienceMonitor> ambience;
    if (opts.ambience) {
        ambience.reset(new keel::AmbienceMonitor(keel::Ambience::defaultSources()));
        ambience->refreshNow();
        state.setAmbience(ambience->values());
        QObject::connect(ambience.data(), &keel::AmbienceMonitor::changed,
                         &state, &keel::ShellState::setAmbience);
        ambience->startWatching();
    }

    // Peer D-Bus for the app.
    const bool portraitPrimary = !QGuiApplication::primaryScreen()
            || QGuiApplication::primaryScreen()->primaryOrientation() == Qt::PortraitOrientation;
    keel::ShellService service(&state, portraitPrimary);
    if (!service.listen(opts.busAddress))
        return 1;

    // Compositor.
    QString socket = opts.socketName;
    if (socket.isEmpty()) {
        const QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
        socket = keel::LaunchConfig::pickSocketName(runtimeDir, QGuiApplication::applicationPid());
    }
    if (socket.isEmpty()) {
        qCCritical(keel::lcKeelShell) << "cannot find a free Wayland socket name";
        return 1;
    }

    SelectedBackend backend(&state);
    keel::BackendConfig config;
    config.socketName = socket;
    config.windowTitle = opts.appTitle.isEmpty() ? QFileInfo(opts.program).fileName()
                                                 : opts.appTitle;
    config.followKeyboard = opts.followKeyboard;
    config.coverEnabled = opts.coverEnabled;
    config.coverTitle = opts.coverTitle;

    QScopedPointer<Reporter> reporter;
    const QString reportPath = QString::fromLocal8Bit(qgetenv("KEEL_SHELL_REPORT"));
    if (!reportPath.isEmpty())
        reporter.reset(new Reporter(&backend, reportPath));

    if (!backend.start(config)) {
        if (!backend.errorString().isEmpty())
            qCCritical(keel::lcKeelShell).noquote() << backend.errorString();
        qCCritical(keel::lcKeelShell).noquote() << "cannot start the nested compositor on" << socket;
        return 1;
    }
    // Later fatal errors (e.g. no OpenGL context for a cover window): log
    // once, then stop the app and exit with 1.
    bool fatal = false;
    auto onFatal = [&fatal](const QString &message) {
        if (fatal)
            return false;
        fatal = true;
        qCCritical(keel::lcKeelShell).noquote() << message;
        return true;
    };
    qCInfo(keel::lcKeelShell).noquote() << "backend" << backend.name() + QStringLiteral(", WAYLAND_DISPLAY=")
            + backend.socketName() + QStringLiteral(", KEEL_SHELL_DBUS=") + service.address();

    if (opts.program.isEmpty()) {
        // Like qt-runner without arguments: just serve the socket.
        std::cout << backend.socketName().toStdString() << "\n" << std::flush;
        QObject::connect(&unixSignals, &keel::UnixSignals::terminateRequested, &app,
                         []() { QGuiApplication::quit(); });
        QObject::connect(&backend, &keel::Backend::closeRequested, &app,
                         []() { QGuiApplication::quit(); });
        QObject::connect(&backend, &keel::Backend::fatalError, &app,
                         [&](const QString &message) {
            if (onFatal(message))
                QGuiApplication::exit(1);
        });
        return QGuiApplication::exec();
    }

    keel::LaunchConfig::EnvInputs envIn;
    envIn.socketName = backend.socketName();
    envIn.busAddress = service.address();
    envIn.dpi = dpi;
    envIn.scaleFactor = opts.scaleFactor;
    envIn.clientShell = opts.clientShell;
    envIn.coverTitle = opts.coverTitle;
    envIn.coverEnabled = opts.coverEnabled;
    envIn.qtScaling = opts.qtScaling;
    QProcessEnvironment env = keel::LaunchConfig::buildEnvironment(
            QProcessEnvironment::systemEnvironment(), envIn, opts.extraEnv);
    if (ambience)
        keel::Ambience::applyToEnvironment(ambience->sources(), ambience->values(), &env);

    keel::Runner runner(opts.program, opts.arguments, env);
    QObject::connect(&runner, &keel::Runner::exited, &app, [&app, &fatal](int code, bool crashed) {
        qCInfo(keel::lcKeelShell).nospace() << "app exited with code " << code
                                            << (crashed ? " (crashed)" : "");
        QGuiApplication::exit(fatal || crashed ? 1 : code);
    });
    QObject::connect(&backend, &keel::Backend::fatalError, &runner, [&](const QString &message) {
        if (!onFatal(message))
            return;
        if (runner.running())
            runner.stop(0);       // SIGTERM now; Runner::exited then ends keel-shell
        else
            QGuiApplication::exit(1);
    });
    QObject::connect(&backend, &keel::Backend::closeRequested, &runner, [&]() {
        state.requestClose();                 // D-Bus CloseRequested to the app
        runner.stop(opts.closeGraceMs);        // then SIGTERM, then SIGKILL
    });
    QObject::connect(&unixSignals, &keel::UnixSignals::terminateRequested, &runner, [&](int) {
        if (!runner.running()) {
            QGuiApplication::exit(0);
            return;
        }
        // Lipstick sends SIGTERM when the user closes the app: give it a
        // moment to act on CloseRequested, then pass the SIGTERM on.
        state.requestClose();
        runner.stop(qMin(opts.closeGraceMs, kSigtermGraceMs));
    });

    runner.start();
    return QGuiApplication::exec();
}

#include "main.moc"
