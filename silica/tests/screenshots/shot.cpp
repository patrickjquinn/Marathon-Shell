// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel-silica-shot: renders one reference scene (scenes/*.qml) offscreen and
// saves it as PNG with QQuickItem::grabToImage(), for side-by-side comparison
// with Silica on a device (keel/README.md, tier C).
//
//   keel-silica-shot <scene.qml> <out.png>
//
// The scene root is either a Window (an ApplicationWindow) or an Item, which
// is shown in a window of its own size. Scene properties read by this tool:
//   shotDelay (int, ms)      time to settle before acting (default 1200)
//   shotDrag (int, px)       if > 0, press at shotDragY and drag down by this
//                            many pixels without releasing (opens a pulley)
//   shotDragY (int, px)      start of the drag (default a quarter down)
// A scene may also define function shotPrepare(), called before the drag.
// Exit status 0 on success; QML warnings are printed and, with --strict,
// make the run fail.

#include <QDir>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QTest>
#include <QTimer>

namespace {
int g_warnings = 0;
QtMessageHandler g_prev = nullptr;

void handler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (type == QtWarningMsg || type == QtCriticalMsg)
        ++g_warnings;
    if (g_prev)
        g_prev(type, ctx, msg);
}

void settle(int ms)
{
    QElapsedTimer t;
    t.start();
    while (t.elapsed() < ms) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        QTest::qWait(5);
    }
}
} // namespace

int main(int argc, char **argv)
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");
    if (qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND"))
        qputenv("QT_QUICK_BACKEND", "software");
    QGuiApplication app(argc, argv);
    QStringList args = QGuiApplication::arguments();
    const bool strict = args.removeAll(QStringLiteral("--strict")) > 0;
    if (args.size() != 3) {
        fprintf(stderr, "usage: keel-silica-shot [--strict] <scene.qml> <out.png>\n");
        return 2;
    }
    g_prev = qInstallMessageHandler(handler);

    QQmlEngine engine;
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QGuiApplication::quit);
    QQmlComponent component(&engine, QUrl::fromLocalFile(QDir::current().absoluteFilePath(args.at(1))));
    QObject *root = component.create();
    if (!root) {
        fprintf(stderr, "%s\n", qPrintable(component.errorString()));
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(root);
    if (!window) {
        auto *item = qobject_cast<QQuickItem *>(root);
        if (!item) {
            fprintf(stderr, "scene root is neither a Window nor an Item\n");
            return 1;
        }
        window = new QQuickWindow;
        window->resize(static_cast<int>(item->width()), static_cast<int>(item->height()));
        item->setParentItem(window->contentItem());
    }
    window->show();
    if (!QTest::qWaitForWindowExposed(window, 5000)) {
        fprintf(stderr, "window not exposed\n");
        return 1;
    }
    const QVariant delay = root->property("shotDelay");
    settle(delay.isValid() ? delay.toInt() : 1200);

    if (root->metaObject()->indexOfMethod("shotPrepare()") >= 0)
        QMetaObject::invokeMethod(root, "shotPrepare");
    settle(300);

    const int drag = root->property("shotDrag").toInt();
    if (drag > 0) {
        const QVariant dy = root->property("shotDragY");
        const QPoint start(window->width() / 2, dy.isValid() ? dy.toInt() : window->height() / 4);
        QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
        const int steps = 40;
        for (int i = 1; i <= steps; ++i) {
            QTest::mouseMove(window, start + QPoint(0, drag * i / steps), 16);
        }
        settle(800);
    }

    QSharedPointer<QQuickItemGrabResult> grab = window->contentItem()->grabToImage();
    if (!grab) {
        fprintf(stderr, "grabToImage failed\n");
        return 1;
    }
    bool done = false;
    QObject::connect(grab.data(), &QQuickItemGrabResult::ready, [&] { done = true; });
    QElapsedTimer t;
    t.start();
    while (!done && t.elapsed() < 5000)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    if (!done || !grab->saveToFile(args.at(2))) {
        fprintf(stderr, "could not save %s\n", qPrintable(args.at(2)));
        return 1;
    }
    if (drag > 0)
        QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier,
                            QPoint(window->width() / 2, window->height() / 2));
    fprintf(stderr, "%s: %d warning(s)\n", qPrintable(args.at(2)), g_warnings);
    return strict && g_warnings > 0 ? 3 : 0;
}
