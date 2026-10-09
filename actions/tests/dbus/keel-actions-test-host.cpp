// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// A Keel app without a window, for the D-Bus and MCP tests: loads a QML
// file of declarations (default: the notes test app) with the Keel.Actions
// runtime, which serves it on the session bus. Started by D-Bus activation
// with --keel-actions, like an app's generated .service file does.
//
//   keel-actions-test-host [--keel-actions] [--native=<lib.so>]
//                          [--no-env-manifest] [file.qml]
// --native loads a Rust cdylib with #[keel::action]s and keel::manifest!()
// RTLD_LOCAL (as booster-keel loads apps); --no-env-manifest ignores
// KEEL_ACTIONS_MANIFEST so the compiled-in manifest is used.
// Environment: KEEL_ACTIONS_MANIFEST (the generated actions.json),
// KEEL_ACTIONS_IDLE_MS.

#include <QGuiApplication>
#include <QLibrary>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QUrl>

#include <memory>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QString file = QStringLiteral(KEEL_ACTIONS_TEST_APP);
    QLibrary native;
    for (const QString &arg : QCoreApplication::arguments().mid(1)) {
        if (arg.startsWith(QLatin1String("--native="))) {
            native.setFileName(arg.mid(9));
            if (!native.load()) {
                qWarning().noquote() << native.errorString();
                return 1;
            }
        } else if (arg == QLatin1String("--no-env-manifest")) {
            qunsetenv("KEEL_ACTIONS_MANIFEST");
        } else if (!arg.startsWith(QLatin1String("--"))) {
            file = arg;
        }
    }
    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    QQmlComponent component(&engine, QUrl::fromLocalFile(file));
    const std::unique_ptr<QObject> root(component.create());
    if (!root) {
        qWarning().noquote() << component.errorString();
        return 1;
    }
    return QGuiApplication::exec();
}
