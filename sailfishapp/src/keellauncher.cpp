// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's launcher (keellauncher.h, ADR-0016).

#include "keellauncher.h"
#include "keellauncher_p.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlDebuggingEnabler>
#include <QQuickView>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QWindow>

#include <QDir>

#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#if !defined(KEEL_QT5COMPAT_DIR)
// The packaged location on 64-bit Sailfish (%{_libdir}/keel/qt5compat);
// the CMake build passes its own.
#define KEEL_QT5COMPAT_DIR "/usr/lib64/keel/qt5compat"
#endif

namespace {

// Booster state. The argv array is what the booster's QGuiApplication was
// constructed with: QCoreApplication keeps a reference to the count and a
// pointer to the array, so refilling both changes arguments() without
// private Qt API (MDeclarativeCache does the same through private API).
constexpr int kMaxArgs = 64;
int g_boosterArgc = 1;
char *g_boosterArgv[kMaxArgs + 1] = { const_cast<char *>("booster-keel"), nullptr };
bool g_boosted = false;
bool g_boosterApp = false;
QQuickView *g_boosterView = nullptr;

bool envIs(const char *name, const char *value)
{
    const char *v = std::getenv(name);
    return v && std::strcmp(v, value) == 0;
}

bool envSet(const char *name)
{
    const char *v = std::getenv(name);
    return v && *v;
}

// Qt checks a cached QML unit against its source by modification time only.
// A reproducible RPM gives every file the build's SOURCE_DATE_EPOCH (the last
// commit's time), so two builds from the same commit install QML with the
// same times, and the app went on running the first build's compiled QML
// (seen with Shoal Camera). Each installed build gets its own cache
// directory instead, named for the executable as installed: the package
// manager writes a new file at every install, so its inode and change time
// differ even when its modification time does not. The other builds'
// directories are removed.
void setQmlCachePerBuild()
{
    if (qEnvironmentVariableIsSet("QML_DISK_CACHE_PATH"))
        return;
    struct stat exe {};
    if (::stat("/proc/self/exe", &exe) != 0)
        return;
    QByteArray name = QFileInfo(QFile::symLinkTarget(QStringLiteral("/proc/self/exe"))).fileName().toUtf8();
    if (name.isEmpty())
        return;
    QByteArray home = qgetenv("XDG_CACHE_HOME");
    if (home.isEmpty())
        home = qgetenv("HOME") + "/.cache";
    const QString base = QString::fromUtf8(home + '/' + name);
    const QString current = QStringLiteral("qmlcache-%1-%2")
                                .arg(qulonglong(exe.st_ino), 0, 16)
                                .arg(qulonglong(exe.st_ctim.tv_sec), 0, 16);
    QDir dir(base);
    const QStringList old = dir.entryList(QStringList() << QStringLiteral("qmlcache*"),
                                          QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : old) {
        if (entry != current)
            QDir(dir.filePath(entry)).removeRecursively();
    }
    qputenv("QML_DISK_CACHE_PATH", QFile::encodeName(dir.filePath(current)));
}

void setDefault(const char *name, const char *value)
{
    if (!envSet(name))
        ::setenv(name, value, 1);
}

std::vector<std::string> procCmdline()
{
    std::vector<std::string> args;
    QFile f(QStringLiteral("/proc/self/cmdline"));
    if (!f.open(QIODevice::ReadOnly))
        return args;
    const QByteArray all = f.readAll();
    for (const QByteArray &a : all.split('\0'))
        args.emplace_back(a.constData(), static_cast<size_t>(a.size()));
    // The file ends with a NUL, which leaves one empty element.
    if (!args.empty() && args.back().empty())
        args.pop_back();
    return args;
}

} // namespace

namespace Keel {

WindowMode windowMode()
{
    if (envIs("KEEL_SHELL", "1"))
        return WindowMode::Shell;
    if (envIs("KEEL_DIRECT", "1"))
        return WindowMode::Direct;
    return WindowMode::Desktop;
}

WindowMode prepareEnvironment()
{
    if (envIs("KEEL_SHELL", "1"))
        return WindowMode::Shell;
    const bool requested = envIs("KEEL_DIRECT", "1");
    const bool detected = !requested && !envIs("KEEL_DIRECT", "0")
            && ::access("/etc/sailfish-release", F_OK) == 0;
    if (!requested && !detected)
        return WindowMode::Desktop;

    // The Sailfish session sets QT_QPA_PLATFORM=wayland for its Qt 5 apps;
    // Keel wants Qt 6's EGL client explicitly. A value set on purpose for
    // a Keel app (anything else) is kept.
    if (!envSet("QT_QPA_PLATFORM") || (detected && envIs("QT_QPA_PLATFORM", "wayland")))
        ::setenv("QT_QPA_PLATFORM", "wayland-egl", 1);
    // Lipstick reads window properties (CATEGORY=cover, BACKGROUND_VISIBLE,
    // the cover link) from qt_extended_surface and shows and hides windows
    // with it. Keel's own wl_shell integration (keel/sailfishapp/waylandshell)
    // speaks it the way Qt 5 did; Qt's wl-shell is the fallback when the
    // plugin is missing (Qt tries the names in order).
    setDefault("QT_WAYLAND_SHELL_INTEGRATION", "keel-wl-shell;wl-shell");
    // wl_shell has no server-side decorations; Qt would draw its own frame.
    setDefault("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
    // Silica sizes are device pixels times Theme.pixelRatio.
    setDefault("QT_ENABLE_HIGHDPI_SCALING", "0");
    // Qt 5 session settings that mean something else, or nothing, to Qt 6.
    if (envIs("QMLSCENE_DEVICE", "customcontext"))
        ::unsetenv("QMLSCENE_DEVICE");
    ::unsetenv("QT_WAYLAND_RESIZE_AFTER_SWAP");
    // Firejail, Sailjail's sandbox, sets QML_DISABLE_DISK_CACHE=1 for every
    // program it starts, so a sandboxed app compiled all of its QML from
    // source at every start (Pacific: a sixth of the QML loader thread). A
    // Keel app's cache directory (~/.cache/<app>/qmlcache) is its own and
    // writable in the sandbox, and Qt checks each cached unit against its
    // source, so the cache comes back. KEEL_QML_DISK_CACHE=0 keeps it off.
    if (envIs("container", "firejail") && envIs("QML_DISABLE_DISK_CACHE", "1")
        && !envIs("KEEL_QML_DISK_CACHE", "0"))
        ::unsetenv("QML_DISABLE_DISK_CACHE");
    setQmlCachePerBuild();
    // KEEL_QML_PROFILE=<port>: QML debugging on, for qmlprofiler (component
    // creation, bindings, animation frames); createView() starts the server
    // on that port. Off unless set.
    if (qEnvironmentVariableIntValue("KEEL_QML_PROFILE") > 0)
        QQmlDebuggingEnabler::enableDebugging(true);
    // Keel's Qt 5 QML API shims (keel/qt5compat) first, as keel-shell does.
    const QByteArray compat(KEEL_QT5COMPAT_DIR);
    if (::access(compat.constData(), F_OK) == 0) {
        const QByteArray current = qgetenv("QML_IMPORT_PATH");
        if (!current.split(':').contains(compat))
            qputenv("QML_IMPORT_PATH", current.isEmpty() ? compat : compat + ':' + current);
    }
    ::setenv("KEEL_DIRECT", "1", 1);
    return WindowMode::Direct;
}

bool boosted()
{
    return g_boosted;
}

QStringList launchArguments()
{
    if (g_boosted)
        return QCoreApplication::arguments();
    QStringList out;
    for (const std::string &a : procCmdline())
        out << QString::fromLocal8Bit(a.data(), static_cast<qsizetype>(a.size()));
    return out;
}

bool headless()
{
    // Keel Actions (ADR-0018): D-Bus activation starts the app with
    // --keel-actions to serve an action without showing its window.
    return envIs("KEEL_ACTIONS_HEADLESS", "1") || launchArguments().contains(QStringLiteral("--keel-actions"));
}

QGuiApplication *application()
{
    if (auto *existing = qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
        return existing;
    // Kept for the life of the process: QCoreApplication refers to them.
    static std::vector<std::string> storage = procCmdline();
    static std::vector<char *> argv;
    static int argc = 0;
    argv.clear();
    for (std::string &s : storage)
        argv.push_back(s.data());
    if (argv.empty()) {
        static char fallback[] = "keel-app";
        argv.push_back(fallback);
    }
    argv.push_back(nullptr);
    argc = static_cast<int>(argv.size()) - 1;
    return SailfishApp::application(argc, argv.data());
}

void showMainWindow(QWindow *window, const QSize &desktopSize)
{
    if (!window || headless())
        return;
    if (windowMode() != WindowMode::Desktop) {
        window->showFullScreen();
        return;
    }
    if (window->width() <= 0 || window->height() <= 0)
        window->resize(desktopSize);
    window->show();
}

namespace detail {

void prepareApplicationDefaults()
{
    // Qt WebEngine (Sailfish.WebView) needs shared GL contexts set before
    // the application exists, in every window mode, boosted or not.
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    if (windowMode() != WindowMode::Direct)
        return;
    // Lipstick composes translucent Silica windows over the ambience; with
    // alpha on every Quick window, the main window and the cover share one
    // surface format (and one GL config), as booster-silica-qt5 sets it.
    QQuickWindow::setDefaultAlphaBuffer(true);
    // Double buffering, swap interval 1: no extra queued frame between the
    // input and the screen (ADR-0016, "Rendering settings").
    // KEEL_SWAP_INTERVAL overrides it (measurement and tuning).
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    bool intervalSet = false;
    const int interval = qEnvironmentVariableIntValue("KEEL_SWAP_INTERVAL", &intervalSet);
    format.setSwapInterval(intervalSet && interval >= 0 ? interval : 1);
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);
}

QQuickView *takeBoosterView()
{
    QQuickView *view = g_boosterView;
    g_boosterView = nullptr;
    return view;
}

} // namespace detail

namespace Booster {

QGuiApplication *createApplication()
{
    ::setenv("KEEL_DIRECT", "1", 1);
    prepareEnvironment();
    detail::prepareApplicationDefaults();
    g_boosterApp = true;
    return new QGuiApplication(g_boosterArgc, g_boosterArgv);
}

void setView(QQuickView *view)
{
    g_boosterView = view;
}

void adoptArguments(int argc, char **argv)
{
    if (!g_boosterApp)
        return;
    const int n = argc < kMaxArgs ? argc : kMaxArgs;
    for (int i = 0; i < n; ++i)
        g_boosterArgv[i] = ::strdup(argv[i]);
    g_boosterArgv[n] = nullptr;
    g_boosterArgc = n;
    g_boosted = true;
    if (n > 0) {
        const QString name = QFileInfo(QString::fromLocal8Bit(argv[0])).fileName();
        QCoreApplication::setApplicationName(name);
        // Qt's Wayland client sends it as the wl_shell class (app id).
        QGuiApplication::setDesktopFileName(name);
    }
    // The launching environment came from the invoker; put Keel's back.
    prepareEnvironment();
    detail::installTranslations(QCoreApplication::instance());
}

} // namespace Booster

} // namespace Keel
