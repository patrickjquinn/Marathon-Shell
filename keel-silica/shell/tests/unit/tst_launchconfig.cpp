// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include <QtTest>

#include <QTemporaryDir>

#include "core/launchconfig.h"

using namespace keel;

class TestLaunchConfig : public QObject
{
    Q_OBJECT
private slots:
    void doubleDash()
    {
        const LaunchOptions o = LaunchConfig::parse(QStringList()
            << "--dpi" << "480" << "--no-cover" << "--" << "/usr/bin/app" << "--app-flag" << "x");
        QVERIFY(o.error.isEmpty());
        QCOMPARE(o.program, QStringLiteral("/usr/bin/app"));
        QCOMPARE(o.arguments, QStringList() << "--app-flag" << "x");
        QCOMPARE(o.dpi, 480);
        QVERIFY(!o.coverEnabled);
    }

    void qtRunnerStyle()
    {
        const LaunchOptions o = LaunchConfig::parse(QStringList()
            << "--verbose" << "/usr/bin/app" << "-style" << "foo");
        QVERIFY(o.error.isEmpty());
        QVERIFY(o.verbose);
        QCOMPARE(o.program, QStringLiteral("/usr/bin/app"));
        QCOMPARE(o.arguments, QStringList() << "-style" << "foo");
    }

    void equalsSyntaxAndRepeatables()
    {
        const LaunchOptions o = LaunchConfig::parse(QStringList()
            << "--socket=keel-test" << "--env" << "A=1" << "--env=B=2=3"
            << "--client-shell=" << "--cover-title" << "X" << "--follow-keyboard" << "--qt-scaling"
            << "--" << "app");
        QVERIFY(o.error.isEmpty());
        QCOMPARE(o.socketName, QStringLiteral("keel-test"));
        QCOMPARE(o.extraEnv, QStringList() << "A=1" << "B=2=3");
        QCOMPARE(o.clientShell, QString());
        QCOMPARE(o.coverTitle, QStringLiteral("X"));
        QVERIFY(o.followKeyboard);
        QVERIFY(o.qtScaling);
    }

    void errors()
    {
        QVERIFY(!LaunchConfig::parse(QStringList() << "--bogus").error.isEmpty());
        QVERIFY(!LaunchConfig::parse(QStringList() << "--dpi").error.isEmpty());
        QVERIFY(!LaunchConfig::parse(QStringList() << "--dpi" << "abc").error.isEmpty());
        QVERIFY(!LaunchConfig::parse(QStringList() << "--env" << "NOEQUALS").error.isEmpty());
        QVERIFY(LaunchConfig::parse(QStringList() << "--help").help);
        QVERIFY(LaunchConfig::parse(QStringList()).program.isEmpty());
    }

    void qt5CompatDirFromBuild()
    {
        // The build passes the library directory it installs into; the
        // shims' directory must follow it, not a hard-coded /usr/lib64.
        const QString dir = LaunchConfig::qt5CompatDir();
        QCOMPARE(dir, QStringLiteral(KEEL_TEST_EXPECTED_LIBDIR "/keel/qt5compat"));
        QVERIFY(QDir::isAbsolutePath(dir));
    }

    void qt5CompatImportPathAlone()
    {
        const QProcessEnvironment env = LaunchConfig::buildEnvironment(
            QProcessEnvironment(), LaunchConfig::EnvInputs(), QStringList());
        QCOMPARE(env.value("QML_IMPORT_PATH"), LaunchConfig::qt5CompatDir());
    }

    void environment()
    {
        QProcessEnvironment base;
        base.insert("QMLSCENE_DEVICE", "customcontext");
        base.insert("QT_WAYLAND_RESIZE_AFTER_SWAP", "1");
        base.insert("WAYLAND_DISPLAY", "../../display/wayland-0");
        base.insert("QT_WAYLAND_SHELL_INTEGRATION", "xdg-shell");
        base.insert("HOME", "/home/defaultuser");
        base.insert("QML_IMPORT_PATH", "/opt/app/qml");

        LaunchConfig::EnvInputs in;
        in.socketName = "../../display/keel-1";
        in.busAddress = "unix:path=/run/user/100000/keel-shell-AbC123/bus";
        in.dpi = 458;
        in.scaleFactor = 2;
        in.clientShell = "wl-shell";
        const QProcessEnvironment env = LaunchConfig::buildEnvironment(base, in,
                                                                       QStringList() << "FOO=bar");
        QCOMPARE(env.value("WAYLAND_DISPLAY"), QStringLiteral("../../display/keel-1"));
        QCOMPARE(env.value("QT_QPA_PLATFORM"), QStringLiteral("wayland"));
        QCOMPARE(env.value("QT_WAYLAND_SHELL_INTEGRATION"), QStringLiteral("wl-shell"));
        QCOMPARE(env.value("QT_WAYLAND_FORCE_DPI"), QStringLiteral("458"));
        QCOMPARE(env.value("QT_SCALE_FACTOR"), QStringLiteral("2"));
        QCOMPARE(env.value("FLATPAK_MALIIT_CONTAINER_DBUS"), in.busAddress);
        QCOMPARE(env.value("KEEL_SHELL_DBUS"), in.busAddress);
        QCOMPARE(env.value("KEEL_SHELL"), QStringLiteral("1"));
        QCOMPARE(env.value("KEEL_SHELL_PROTOCOL"), QStringLiteral("1"));
        QCOMPARE(env.value("QML_IMPORT_PATH"),
                 LaunchConfig::qt5CompatDir() + QStringLiteral(":/opt/app/qml"));
        QCOMPARE(env.value("KEEL_SHELL_COVER_TITLE"), QStringLiteral("keel:cover"));
        QCOMPARE(env.value("KEEL_SHELL_COVER_ENABLED"), QStringLiteral("1"));
        QCOMPARE(env.value("FOO"), QStringLiteral("bar"));
        QCOMPARE(env.value("HOME"), QStringLiteral("/home/defaultuser"));
        QVERIFY(!env.contains("QMLSCENE_DEVICE"));
        QVERIFY(!env.contains("QT_WAYLAND_RESIZE_AFTER_SWAP"));
        QCOMPARE(env.value("QT_ENABLE_HIGHDPI_SCALING"), QStringLiteral("0"));
        QCOMPARE(env.value("QT_WAYLAND_DISABLE_WINDOWDECORATION"), QStringLiteral("1"));

        in.clientShell.clear();
        in.scaleFactor = 1;
        const QProcessEnvironment env2 = LaunchConfig::buildEnvironment(base, in);
        QVERIFY(!env2.contains("QT_WAYLAND_SHELL_INTEGRATION"));
        QVERIFY(!env2.contains("QT_SCALE_FACTOR"));

        in.qtScaling = true;
        QVERIFY(!LaunchConfig::buildEnvironment(base, in).contains("QT_ENABLE_HIGHDPI_SCALING"));
        in.qtScaling = false;
        base.insert("QT_ENABLE_HIGHDPI_SCALING", "1");   // the user's choice wins
        QCOMPARE(LaunchConfig::buildEnvironment(base, in).value("QT_ENABLE_HIGHDPI_SCALING"),
                 QStringLiteral("1"));
    }

    void socketNames()
    {
        QTemporaryDir root;
        QVERIFY(root.isValid());
        // No ../../display: private name in the runtime dir.
        const QString runtime = root.filePath("run/user/100000");
        QVERIFY(QDir().mkpath(runtime));
        QCOMPARE(LaunchConfig::pickSocketName(runtime, 77), QStringLiteral("keel-shell-77-0"));
        QFile taken(runtime + "/keel-shell-77-0");
        QVERIFY(taken.open(QIODevice::WriteOnly));
        taken.close();
        QCOMPARE(LaunchConfig::pickSocketName(runtime, 77), QStringLiteral("keel-shell-77-1"));

        // Sailfish layout: next to Lipstick's socket in /run/display.
        QVERIFY(QDir().mkpath(root.filePath("run/display")));
        QCOMPARE(LaunchConfig::pickSocketName(runtime, 77), QStringLiteral("../../display/keel-1"));
    }
};

QTEST_GUILESS_MAIN(TestLaunchConfig)
#include "tst_launchconfig.moc"
