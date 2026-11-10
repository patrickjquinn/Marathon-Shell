// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Regression test for the qemu abort: keel-shell under QT_QPA_PLATFORM=minimal
// (no OpenGL) reached Qt Quick's qFatal("Failed to create OpenGL context")
// when it showed its first Lipstick window. It must instead detect the
// missing OpenGL and fail start() with a clear error. This runs on the
// platform that crashed ("minimal"); the Qt 5.6 backend that uses the check
// only builds on Sailfish (checked under qemu, see README.md).

#include <QGuiApplication>
#include <QSignalSpy>
#include <QtTest>

#include "core/backend.h"
#include "core/graphics.h"
#include "core/shellstate.h"

using namespace keel;

namespace {

// Stands in for Backend56::start(): fails the way it does without OpenGL.
class NoGLBackend : public Backend
{
public:
    using Backend::Backend;

    bool start(const BackendConfig &config) override
    {
        setConfig(config);
        const QString reason = openGLUnavailableReason();
        if (!reason.isEmpty()) {
            reportFatalError(reason);
            return false;
        }
        return true;
    }
    QString socketName() const override { return QString(); }
    QString name() const override { return QStringLiteral("test"); }

    void fail(const QString &message) { reportFatalError(message); }
};

} // namespace

class TestGraphics : public QObject
{
    Q_OBJECT
private slots:
    void minimalPlatformHasNoOpenGL()
    {
        QCOMPARE(QGuiApplication::platformName(), QStringLiteral("minimal"));
        const QString reason = openGLUnavailableReason();
        QVERIFY(!reason.isEmpty());
        QVERIFY2(reason.contains(QLatin1String("\"minimal\"")), qPrintable(reason));
        QVERIFY2(reason.contains(QLatin1String("OpenGL")), qPrintable(reason));
    }

    void startFailsCleanlyWithoutOpenGL()
    {
        ShellState state;
        NoGLBackend backend(&state);
        QSignalSpy spy(&backend, &Backend::fatalError);
        QVERIFY(!backend.start(BackendConfig()));
        QCOMPARE(spy.count(), 1);
        QCOMPARE(backend.errorString(), openGLUnavailableReason());
        QVERIFY(backend.outerWindowIds().isEmpty());   // no window was shown
    }

    void firstFatalErrorIsKept()
    {
        ShellState state;
        NoGLBackend backend(&state);
        QSignalSpy spy(&backend, &Backend::fatalError);
        backend.fail(QStringLiteral("first"));
        backend.fail(QStringLiteral("second"));
        QCOMPARE(spy.count(), 2);
        QCOMPARE(backend.errorString(), QStringLiteral("first"));
    }

    void sceneGraphMessage()
    {
        const QString m = sceneGraphFailureMessage(2, WindowRole::Cover,
                                                   QStringLiteral("Failed to create OpenGL context\n"));
        QCOMPARE(m, QStringLiteral("cannot render Lipstick window 2 (cover): "
                                   "Failed to create OpenGL context"));
    }
};

int main(int argc, char *argv[])
{
    // The platform plugin keel-shell aborted on under qemu, whatever the
    // caller (ctest sets offscreen) asked for.
    qputenv("QT_QPA_PLATFORM", "minimal");
    QGuiApplication app(argc, argv);
    TestGraphics test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_graphics.moc"
