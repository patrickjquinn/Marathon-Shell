// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// pacific-minibrowser [options] [url]
//   --silica              Sailfish Silica (Keel) chrome instead of plain Qt Quick
//   --screenshot <file>   save the window to <file> once the page has loaded
//                         (plus --settle <ms>, default 1500) and quit
//   --snapshot            print WebView.agentSnapshot() of the page as JSON, quit
//   --headless            no window at all: a headless WebView (Pilot's mode);
//                         with --snapshot, the whole agent path without a GPU frame
//   --timeout <s>         give up after <s> seconds (default 60), exit 2
//   --script-input        WebView.ScriptInput (Atlantic's text entry) instead of
//                         WebKit's native input-method context
// Logs load events, title changes, console messages and process crashes on
// stderr, prefixed "minibrowser:".

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QTimer>
#include <QUrl>

int main(int argc, char* argv[])
{
    // WPE frames arrive as EGLImages bound into GL textures: the scene graph
    // must run on OpenGL (ES), never Vulkan or software.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("pacific-minibrowser"));
    QCoreApplication::setOrganizationName(QStringLiteral("org.shipwright"));

    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addPositionalArgument(QStringLiteral("url"), QStringLiteral("Page to open"));
    QCommandLineOption silica(QStringLiteral("silica"), QStringLiteral("Use Sailfish Silica chrome"));
    QCommandLineOption screenshot(QStringLiteral("screenshot"), QStringLiteral("Save the window and quit"), QStringLiteral("file"));
    QCommandLineOption settle(QStringLiteral("settle"), QStringLiteral("Wait after load (ms)"), QStringLiteral("ms"), QStringLiteral("1500"));
    QCommandLineOption snapshot(QStringLiteral("snapshot"), QStringLiteral("Print the agent snapshot and quit"));
    QCommandLineOption headless(QStringLiteral("headless"), QStringLiteral("No window: headless WebView"));
    QCommandLineOption timeout(QStringLiteral("timeout"), QStringLiteral("Give up after s seconds"), QStringLiteral("s"), QStringLiteral("60"));
    QCommandLineOption scriptInput(QStringLiteral("script-input"), QStringLiteral("Script text entry"));
    parser.addOptions({ silica, screenshot, settle, snapshot, headless, timeout, scriptInput });
    parser.process(app);

    const QStringList args = parser.positionalArguments();
    const QUrl url = args.isEmpty() ? QUrl(QStringLiteral("https://en.wikipedia.org/wiki/Pacific_Ocean"))
                                    : QUrl::fromUserInput(args.first());

    QQmlApplicationEngine engine;
    engine.setInitialProperties({
        { QStringLiteral("startUrl"), url },
        { QStringLiteral("screenshotPath"), parser.value(screenshot) },
        { QStringLiteral("settleMs"), parser.value(settle).toInt() },
        { QStringLiteral("printSnapshot"), parser.isSet(snapshot) },
        { QStringLiteral("headlessMode"), parser.isSet(headless) },
        { QStringLiteral("scriptInput"), parser.isSet(scriptInput) },
    });
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(3); },
        Qt::QueuedConnection);
    engine.loadFromModule("PacificMiniBrowser", parser.isSet(silica) ? "SilicaMain" : "Main");

    QTimer::singleShot(parser.value(timeout).toInt() * 1000, &app, [] {
        qWarning("minibrowser: timed out");
        QCoreApplication::exit(2);
    });
    return QGuiApplication::exec();
}
