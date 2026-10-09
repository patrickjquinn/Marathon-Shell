// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Command line and child environment for keel-shell.
//
//   keel-shell [options] -- /usr/bin/myapp [app args...]
//   keel-shell [options] /usr/bin/myapp [app args...]      (qt-runner style)

#ifndef KEEL_LAUNCHCONFIG_H
#define KEEL_LAUNCHCONFIG_H

#include <QProcessEnvironment>
#include <QString>
#include <QStringList>

namespace keel {

struct LaunchOptions {
    QString program;
    QStringList arguments;

    QString socketName;          // --socket NAME (relative to XDG_RUNTIME_DIR or absolute)
    QString busAddress;          // --bus-address ADDR (QDBusServer address)
    int dpi = 0;                 // --dpi N (0 = physical DPI of the primary screen)
    int scaleFactor = 0;         // --scale N (QT_SCALE_FACTOR; 0 = unset)
    bool coverEnabled = true;    // --no-cover
    bool followKeyboard = false; // --follow-keyboard (shrink main window for the VKB)
    bool ambience = true;        // --no-ambience
    bool qtScaling = false;      // --qt-scaling (let Qt6 derive a devicePixelRatio from the DPI)
    QString clientShell = QStringLiteral("wl-shell");   // --client-shell NAME|"" (QT_WAYLAND_SHELL_INTEGRATION)
    QString coverTitle;          // --cover-title MARKER
    QString appTitle;            // --title TEXT (outer window title)
    int closeGraceMs = 3000;     // --close-grace MS
    QStringList extraEnv;        // --env NAME=VALUE (repeatable)
    bool verbose = false;        // --verbose
    bool help = false;           // --help
    bool version = false;        // --version

    QString error;               // parse error, if any
};

class LaunchConfig
{
public:
    // args excludes argv[0].
    static LaunchOptions parse(const QStringList &args);
    static QString usage(const QString &argv0);

    // Picks a Wayland socket name that does not exist yet. On Sailfish,
    // Lipstick's socket is $XDG_RUNTIME_DIR/../../display/wayland-0 and
    // qt-runner places nested sockets next to it (the sandbox whitelists
    // /run/display); we do the same when that directory is writable, and fall
    // back to "keel-shell-<pid>-<n>" in XDG_RUNTIME_DIR.
    static QString pickSocketName(const QString &runtimeDir, qint64 pid);

    // Import directory of keel/qt5compat, "<libdir>/keel/qt5compat". Fixed
    // at build time (KEEL_QT5COMPAT_DIR) so that it follows %{_libdir}:
    // /usr/lib64 on aarch64, /usr/lib on 32-bit targets.
    static QString qt5CompatDir();

    struct EnvInputs {
        QString socketName;
        QString busAddress;
        int dpi = 0;
        int scaleFactor = 0;
        QString clientShell;
        QString coverTitle;
        bool coverEnabled = true;
        bool qtScaling = false;
    };

    // Environment for the nested app. Based on qt-runner's Runner:
    // WAYLAND_DISPLAY, QT_WAYLAND_FORCE_DPI, FLATPAK_MALIIT_CONTAINER_DBUS,
    // drops QMLSCENE_DEVICE=customcontext and QT_WAYLAND_RESIZE_AFTER_SWAP;
    // plus the KEEL_SHELL_* contract (PROTOCOL.md).
    static QProcessEnvironment buildEnvironment(const QProcessEnvironment &base,
                                                const EnvInputs &in,
                                                const QStringList &extraEnv = QStringList());
};

} // namespace keel

#endif // KEEL_LAUNCHCONFIG_H
