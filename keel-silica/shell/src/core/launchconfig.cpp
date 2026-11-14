// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "launchconfig.h"

#include <QDir>
#include <QFileInfo>

#include "coverpolicy.h"

#ifndef KEEL_QT5COMPAT_DIR
#error "KEEL_QT5COMPAT_DIR must be set by the build (keel-shell.pro or CMakeLists.txt)"
#endif

namespace keel {

QString LaunchConfig::qt5CompatDir()
{
    return QStringLiteral(KEEL_QT5COMPAT_DIR);
}

static bool takeValue(const QStringList &args, int *i, const QString &name, QString *out,
                      QString *error)
{
    const QString &arg = args.at(*i);
    const QString eqPrefix = name + QLatin1Char('=');
    if (arg.startsWith(eqPrefix)) {
        *out = arg.mid(eqPrefix.size());
        return true;
    }
    if (arg == name) {
        if (*i + 1 >= args.size()) {
            *error = QStringLiteral("missing value for %1").arg(name);
            return true;
        }
        *i += 1;
        *out = args.at(*i);
        return true;
    }
    return false;
}

LaunchOptions LaunchConfig::parse(const QStringList &args)
{
    LaunchOptions o;
    int i = 0;
    for (; i < args.size(); ++i) {
        const QString &a = args.at(i);
        QString v;
        if (a == QLatin1String("--")) {
            ++i;
            break;
        }
        if (!a.startsWith(QLatin1Char('-')))
            break;   // first non-option: the program (qt-runner style)
        if (a == QLatin1String("--help") || a == QLatin1String("-h")) {
            o.help = true;
        } else if (a == QLatin1String("--version")) {
            o.version = true;
        } else if (a == QLatin1String("--verbose") || a == QLatin1String("-v")) {
            o.verbose = true;
        } else if (a == QLatin1String("--no-cover")) {
            o.coverEnabled = false;
        } else if (a == QLatin1String("--follow-keyboard")) {
            o.followKeyboard = true;
        } else if (a == QLatin1String("--no-ambience")) {
            o.ambience = false;
        } else if (a == QLatin1String("--qt-scaling")) {
            o.qtScaling = true;
        } else if (takeValue(args, &i, QStringLiteral("--socket"), &v, &o.error)) {
            o.socketName = v;
        } else if (takeValue(args, &i, QStringLiteral("--bus-address"), &v, &o.error)) {
            o.busAddress = v;
        } else if (takeValue(args, &i, QStringLiteral("--dpi"), &v, &o.error)) {
            bool ok = false;
            o.dpi = v.toInt(&ok);
            if (!ok || o.dpi < 0)
                o.error = QStringLiteral("invalid --dpi value: %1").arg(v);
        } else if (takeValue(args, &i, QStringLiteral("--scale"), &v, &o.error)) {
            bool ok = false;
            o.scaleFactor = v.toInt(&ok);
            if (!ok || o.scaleFactor < 0)
                o.error = QStringLiteral("invalid --scale value: %1").arg(v);
        } else if (takeValue(args, &i, QStringLiteral("--client-shell"), &v, &o.error)) {
            o.clientShell = v;
        } else if (takeValue(args, &i, QStringLiteral("--cover-title"), &v, &o.error)) {
            o.coverTitle = v;
        } else if (takeValue(args, &i, QStringLiteral("--title"), &v, &o.error)) {
            o.appTitle = v;
        } else if (takeValue(args, &i, QStringLiteral("--close-grace"), &v, &o.error)) {
            bool ok = false;
            o.closeGraceMs = v.toInt(&ok);
            if (!ok || o.closeGraceMs < 0)
                o.error = QStringLiteral("invalid --close-grace value: %1").arg(v);
        } else if (takeValue(args, &i, QStringLiteral("--env"), &v, &o.error)) {
            if (!v.contains(QLatin1Char('=')))
                o.error = QStringLiteral("--env expects NAME=VALUE, got %1").arg(v);
            else
                o.extraEnv << v;
        } else {
            o.error = QStringLiteral("unknown option: %1").arg(a);
        }
        if (!o.error.isEmpty())
            return o;
    }
    if (i < args.size()) {
        o.program = args.at(i);
        o.arguments = args.mid(i + 1);
    }
    return o;
}

QString LaunchConfig::usage(const QString &argv0)
{
    return QStringLiteral(
        "Usage: %1 [options] -- /path/to/app [app arguments]\n"
        "\n"
        "Runs a Qt6 (Keel) app on a private nested Wayland compositor and maps its\n"
        "windows into Lipstick: main surface -> app window, cover surface -> a\n"
        "second window with CATEGORY=cover.\n"
        "\n"
        "Options:\n"
        "  --socket NAME          Wayland socket name for the app (default: auto)\n"
        "  --bus-address ADDR     peer D-Bus server address (default: auto)\n"
        "  --dpi N                QT_WAYLAND_FORCE_DPI for the app (default: physical DPI)\n"
        "  --scale N              QT_SCALE_FACTOR for the app\n"
        "  --client-shell NAME    QT_WAYLAND_SHELL_INTEGRATION for the app\n"
        "                         (default: wl-shell; empty string leaves it unset)\n"
        "  --cover-title MARKER   cover title marker (default: keel:cover)\n"
        "  --no-cover             treat cover surfaces as ordinary windows\n"
        "  --follow-keyboard      shrink the main window while the keyboard is open\n"
        "  --no-ambience          do not read or forward the ambience\n"
        "  --qt-scaling           let Qt6 scale by DPI (default: devicePixelRatio 1,\n"
        "                         Silica-style pixel metrics via Theme.pixelRatio)\n"
        "  --title TEXT           title of the Lipstick-facing windows\n"
        "  --close-grace MS       wait after CloseRequested before SIGTERM (default 3000)\n"
        "  --env NAME=VALUE       extra environment for the app (repeatable)\n"
        "  --verbose              log surface mapping decisions\n"
        "  --version, --help\n").arg(argv0);
}

QString LaunchConfig::pickSocketName(const QString &runtimeDir, qint64 pid)
{
    QDir runtime(runtimeDir);
    const QString displayRel = QStringLiteral("../../display");
    const QFileInfo displayDir(runtime.absoluteFilePath(displayRel));
    if (!runtimeDir.isEmpty() && displayDir.isDir() && displayDir.isWritable()) {
        for (int i = 1; i < 1000; ++i) {
            const QString candidate = QStringLiteral("%1/keel-%2").arg(displayRel).arg(i);
            if (!runtime.exists(candidate))
                return candidate;
        }
    }
    for (int i = 0; i < 1000; ++i) {
        const QString candidate = QStringLiteral("keel-shell-%1-%2").arg(pid).arg(i);
        if (!runtime.exists(candidate))
            return candidate;
    }
    return QString();
}

QProcessEnvironment LaunchConfig::buildEnvironment(const QProcessEnvironment &base,
                                                   const EnvInputs &in,
                                                   const QStringList &extraEnv)
{
    QProcessEnvironment env = base;

    env.insert(QStringLiteral("WAYLAND_DISPLAY"), in.socketName);
    env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("wayland"));
    if (in.clientShell.isEmpty())
        env.remove(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"));
    else
        env.insert(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"), in.clientShell);

    // From qt-runner: the Qt6 Maliit input context plugin
    // (qt6-sfos-maliit-platforminputcontext) reads orientation/active state
    // from this peer bus and reports the keyboard rectangle back to it.
    if (!in.busAddress.isEmpty())
        env.insert(QStringLiteral("FLATPAK_MALIIT_CONTAINER_DBUS"), in.busAddress);

    // From qt-runner: the Sailfish scenegraph "customcontext" does not exist
    // in the nested Qt, and QT_WAYLAND_RESIZE_AFTER_SWAP breaks input.
    if (env.value(QStringLiteral("QMLSCENE_DEVICE")) == QLatin1String("customcontext"))
        env.remove(QStringLiteral("QMLSCENE_DEVICE"));
    env.remove(QStringLiteral("QT_WAYLAND_RESIZE_AFTER_SWAP"));

    if (in.dpi > 0)
        env.insert(QStringLiteral("QT_WAYLAND_FORCE_DPI"), QString::number(in.dpi));
    // Qt6 turns QT_WAYLAND_FORCE_DPI into a devicePixelRatio of dpi/96
    // (about 4.8 on a 458 dpi phone). Silica QML is written in device pixels
    // scaled by Theme.pixelRatio, so Keel apps run unscaled by default.
    if (!in.qtScaling && !base.contains(QStringLiteral("QT_ENABLE_HIGHDPI_SCALING")))
        env.insert(QStringLiteral("QT_ENABLE_HIGHDPI_SCALING"), QStringLiteral("0"));
    // Lipstick windows have no decorations; without this Qt6 draws
    // client-side decorations around every nested window.
    if (!base.contains(QStringLiteral("QT_WAYLAND_DISABLE_WINDOWDECORATION")))
        env.insert(QStringLiteral("QT_WAYLAND_DISABLE_WINDOWDECORATION"), QStringLiteral("1"));
    if (in.scaleFactor > 1)
        env.insert(QStringLiteral("QT_SCALE_FACTOR"), QString::number(in.scaleFactor));

    // Keel contract (PROTOCOL.md).
    env.insert(QStringLiteral("KEEL_SHELL"), QStringLiteral("1"));
    env.insert(QStringLiteral("KEEL_SHELL_PROTOCOL"), QStringLiteral("1"));
    // Qt 5 QML API shims (keel/qt5compat) come before anything the app or
    // the user sets, so unchanged Sailfish apps find QtGraphicalEffects,
    // QtFeedback, QtMultimedia 5.x and the Qt 5 QtQuick types.
    QStringList importPath{qt5CompatDir()};
    const QString inherited = base.value(QStringLiteral("QML_IMPORT_PATH"));
    if (!inherited.isEmpty())
        importPath << inherited;
    env.insert(QStringLiteral("QML_IMPORT_PATH"), importPath.join(QLatin1Char(':')));
    if (!in.busAddress.isEmpty())
        env.insert(QStringLiteral("KEEL_SHELL_DBUS"), in.busAddress);
    env.insert(QStringLiteral("KEEL_SHELL_COVER_TITLE"),
               in.coverTitle.isEmpty() ? CoverPolicy::defaultTitleMarker() : in.coverTitle);
    env.insert(QStringLiteral("KEEL_SHELL_COVER_ENABLED"), in.coverEnabled ? QStringLiteral("1")
                                                                           : QStringLiteral("0"));
    if (in.dpi > 0)
        env.insert(QStringLiteral("KEEL_SHELL_DPI"), QString::number(in.dpi));

    for (const QString &kv : extraEnv) {
        const int eq = kv.indexOf(QLatin1Char('='));
        if (eq > 0)
            env.insert(kv.left(eq), kv.mid(eq + 1));
    }
    return env;
}

} // namespace keel
