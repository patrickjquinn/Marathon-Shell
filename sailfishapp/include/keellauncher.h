// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's launcher: how a Keel app starts on a phone (ADR-0016). Part of
// libkeel-sailfishapp; SailfishApp::application() and createView() use it,
// so SDK-style apps get it without code changes. Apps whose main() is not
// SailfishApp::main() (the Rust apps) call Keel::application() and
// Keel::launchArguments() directly.
//
// Window modes:
//   Direct  - the default on Sailfish OS: the app's windows are Lipstick
//             windows (Qt 6 wayland-egl + wl_shell + qt_extended_surface,
//             the protocol path of native Qt 5 Silica apps, through Keel's
//             keel-wl-shell integration). No keel-shell.
//   Shell   - under keel-shell (KEEL_SHELL=1), the opt-in fallback.
//   Desktop - anything else: an ordinary Qt window.
//
// Boosting: booster-keel (keel/booster, a mapplauncherd booster) creates
// the QGuiApplication and a QQuickView before any app is launched, then
// loads the app binary and calls its main(). application() and
// SailfishApp::createView() hand those pre-created objects to the app, as
// libsailfishapp does with MDeclarativeCache under booster-silica-qt5.
#ifndef KEEL_LAUNCHER_H
#define KEEL_LAUNCHER_H

#include <QSize>
#include <QStringList>

#include "sailfishapp.h"

class QGuiApplication;
class QQuickView;
class QWindow;

namespace Keel {

enum class WindowMode { Desktop, Direct, Shell };

// Decides the window mode and sets the environment Qt needs for it before
// the QGuiApplication exists. Direct mode, unless the variable is already
// set: QT_QPA_PLATFORM=wayland-egl (also replacing the Sailfish session's
// Qt 5 default "wayland" when the mode was detected rather than requested),
// QT_WAYLAND_SHELL_INTEGRATION="keel-wl-shell;wl-shell" (Keel's shell
// integration, Qt's wl-shell without it), QT_WAYLAND_DISABLE_WINDOWDECORATION=1,
// QT_ENABLE_HIGHDPI_SCALING=0; removes the Qt 5 session's
// QMLSCENE_DEVICE=customcontext and QT_WAYLAND_RESIZE_AFTER_SWAP; puts
// <libdir>/keel/qt5compat first on QML_IMPORT_PATH; sets KEEL_DIRECT=1 for
// Keel's QML modules. Direct mode is chosen when KEEL_DIRECT=1, or on
// Sailfish OS (/etc/sailfish-release) unless KEEL_DIRECT=0 or KEEL_SHELL=1.
// Idempotent.
SAILFISHAPP_EXPORT WindowMode prepareEnvironment();

// The mode prepareEnvironment() chose (from the environment).
SAILFISHAPP_EXPORT WindowMode windowMode();

// True in an app process started by booster-keel.
SAILFISHAPP_EXPORT bool boosted();

// The app's command line: the invoker's when boosted, otherwise the
// process's (/proc/self/cmdline). Usable before application(). A Rust
// main must use this rather than std::env::args(): a boosted app binary is
// dlopen()ed into the booster, and Rust's args are the booster's.
SAILFISHAPP_EXPORT QStringList launchArguments();

// True when the app was started to serve Keel Actions without its window
// (D-Bus activation passes --keel-actions; or KEEL_ACTIONS_HEADLESS=1).
// showMainWindow() then shows nothing; apps that show their view
// themselves check this first (ADR-0018).
SAILFISHAPP_EXPORT bool headless();

// The application object: the booster's when boosted, otherwise created
// from launchArguments() through SailfishApp::application().
SAILFISHAPP_EXPORT QGuiApplication *application();

// Shows an app's main window: full screen on a phone, otherwise `desktopSize`
// (when the window has no size yet).
SAILFISHAPP_EXPORT void showMainWindow(QWindow *window, const QSize &desktopSize = QSize(540, 960));

// For booster-keel only.
namespace Booster {
// Prepares direct mode and creates the QGuiApplication with argv storage
// that adoptArguments() can refill later.
SAILFISHAPP_EXPORT QGuiApplication *createApplication();
// The preloaded view that the next SailfishApp::createView() returns.
SAILFISHAPP_EXPORT void setView(QQuickView *view);
// Before the app's main() runs: the app's argv becomes the application's
// arguments, application name and desktop file name; translations of the
// app are installed; boosted() becomes true.
SAILFISHAPP_EXPORT void adoptArguments(int argc, char **argv);
} // namespace Booster

} // namespace Keel

#endif // KEEL_LAUNCHER_H
