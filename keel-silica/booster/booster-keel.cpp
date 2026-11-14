// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// booster-keel: a mapplauncherd booster for Keel (Qt 6) apps (ADR-0016).
// Written against mapplauncherd's public booster API (libapplauncherd,
// LGPL-2.1, https://github.com/sailfishos/mapplauncherd); its shape follows
// mapplauncherd-booster-silica (booster-silica.cpp, eventhandler.cpp), which
// does the same for Qt 5 Silica apps. No code is copied from either.
//
// Before any app is launched, this process (forked by mapplauncherd's
// daemon) creates the QGuiApplication for direct mode (wayland-egl +
// wl-shell, so the Wayland connection to Lipstick is already open), a
// QQuickView, and compiles and instantiates preload.qml in the view's engine:
// Sailfish.Silica, Keel and the common Silica types are loaded, registered
// and compiled once. When `invoker --type=keel <app>` arrives, mapplauncherd
// dlopen()s the app binary (a PIE that exports main) into this process and
// calls its main(); SailfishApp::application() / Keel::application() and
// SailfishApp::createView() return the objects made here.

#include <booster.h>
#include <connection.h>
#include <daemon.h>
#include <logger.h>

#include <QCoreApplication>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QSocketNotifier>
#include <QTimer>
#include <QUrl>

#include <keellauncher.h>

#include <csignal>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

#ifndef BOOSTER_TYPE
#define BOOSTER_TYPE "keel"
#endif
#ifndef KEEL_BOOSTER_PRELOAD
#define KEEL_BOOSTER_PRELOAD "/usr/share/booster-keel/preload.qml"
#endif

namespace {

int g_hupFds[2] = { -1, -1 };

void onHup(int)
{
    const char c = 1;
    const ssize_t ignored = ::write(g_hupFds[0], &c, 1);
    (void)ignored;
}

class KeelBooster : public Booster
{
public:
    const std::string &boosterType() const override
    {
        static const std::string type = BOOSTER_TYPE;
        return type;
    }

protected:
    bool preload() override
    {
        Keel::Booster::createApplication();
        m_view = new QQuickView;
        Keel::Booster::setView(m_view);
        // Start compiling shortly after start-up, as booster-silica does:
        // when apps are launched back to back, a booster that is used at
        // once need not preload at all.
        const QString file = qEnvironmentVariable("KEEL_BOOSTER_PRELOAD", QStringLiteral(KEEL_BOOSTER_PRELOAD));
        QTimer::singleShot(qEnvironmentVariableIntValue("KEEL_BOOSTER_PRELOAD_DELAY_MS"), m_view, [this, file]() {
            m_component = new QQmlComponent(m_view->engine(), QUrl::fromLocalFile(file),
                                            QQmlComponent::Asynchronous, m_view);
            auto finish = [this]() {
                if (m_component->isError()) {
                    for (const QQmlError &e : m_component->errors())
                        Logger::logError("booster-keel: preload: %s", e.toString().toLocal8Bit().constData());
                    return;
                }
                if (!m_component->isReady())
                    return;
                // Instantiate once (fonts, images, scene graph types), then
                // drop the instance; the compiled types stay in the engine.
                QQmlContext context(m_view->engine());
                delete m_component->create(&context);
                Logger::logInfo("booster-keel: preloaded %s", m_component->url().toString().toLocal8Bit().constData());
            };
            if (m_component->isLoading())
                QObject::connect(m_component, &QQmlComponent::statusChanged, m_view, finish);
            else
                finish();
        });
        return true;
    }

    // Waits for the invoker with Qt's event loop running, so that the
    // Wayland connection, the dconf watch and the asynchronous preload are
    // serviced meanwhile (booster-silica's EventHandler does the same).
    bool receiveDataFromInvoker(int socketFd) override
    {
        if (bootMode())
            return Booster::receiveDataFromInvoker(socketFd);
        setConnection(new Connection(socketFd));

        bool hupHandler = false;
        struct sigaction oldHup {};
        if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, g_hupFds) == 0) {
            // mapplauncherd's daemon sends SIGHUP to idle boosters when it
            // goes away.
            auto *notifier = new QSocketNotifier(g_hupFds[1], QSocketNotifier::Read, qApp);
            QObject::connect(notifier, &QSocketNotifier::activated, qApp, []() { ::_exit(EXIT_SUCCESS); });
            struct sigaction hup {};
            hup.sa_handler = onHup;
            sigemptyset(&hup.sa_mask);
            hup.sa_flags = SA_RESTART;
            hupHandler = ::sigaction(SIGHUP, &hup, &oldHup) == 0;
        }

        bool accepted = false;
        std::thread waiter([this, &accepted]() {
            accepted = connection()->accept(appData());
            QMetaObject::invokeMethod(qApp, &QCoreApplication::quit, Qt::QueuedConnection);
        });
        QCoreApplication::exec();
        waiter.join();
        if (hupHandler)
            ::sigaction(SIGHUP, &oldHup, nullptr);

        // Whatever the preload has not finished is not worth waiting for.
        if (m_component && m_component->isLoading()) {
            delete m_component;
            m_component = nullptr;
        }
        if (!accepted || !connection()->connected())
            return false;
        if (!connection()->receiveApplicationData(appData())) {
            connection()->close();
            return false;
        }
        if (!connection()->isReportAppExitStatusNeeded())
            connection()->close();
        return true;
    }

    // After mapplauncherd has set the app's environment and loaded the app,
    // just before its main(): give the app its own name and arguments.
    void preinit() override
    {
        Keel::Booster::adoptArguments(appData()->argc(), const_cast<char **>(appData()->argv()));
    }

private:
    QQuickView *m_view = nullptr;
    QQmlComponent *m_component = nullptr;
};

} // namespace

int main(int argc, char **argv)
{
    auto *booster = new KeelBooster;
    Daemon daemon(argc, argv);
    daemon.run(booster);
    return 0;
}
