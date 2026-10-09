// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Headless end-to-end test:
//   fake-lipstick (Qt 5.15 compositor, offscreen, speaks qt_extended_surface)
//     <- keel-shell (Qt 5.15 Wayland client + qt515 nested compositor)
//          <- keel-test-client (Qt6, main window + cover window)
// Asserts that keel-shell created two Lipstick-facing surfaces, that exactly
// one of them carries CATEGORY=cover on the wire, that both got content, and
// that the app reached keel-shell's peer D-Bus.

#include <QtTest>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>

#include <csignal>

static QJsonObject readJson(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return QJsonObject();
    return QJsonDocument::fromJson(f.readAll()).object();
}

class TestE2E : public QObject
{
    Q_OBJECT
private slots:
    void initTestCase()
    {
        QVERIFY2(QFile::exists(QStringLiteral(KEEL_SHELL_BIN)), KEEL_SHELL_BIN);
        QVERIFY2(QFile::exists(QStringLiteral(FAKE_LIPSTICK_BIN)), FAKE_LIPSTICK_BIN);
        QVERIFY2(QFile::exists(QStringLiteral(TEST_CLIENT_BIN)), TEST_CLIENT_BIN);
    }

    void mainAndCover_data()
    {
        QTest::addColumn<QString>("clientShell");
        QTest::addColumn<bool>("lateCover");
        QTest::newRow("wl-shell") << "wl-shell" << false;
        QTest::newRow("xdg-shell") << "xdg-shell" << false;
        QTest::newRow("wl-shell, cover title set after show") << "wl-shell" << true;
    }

    void mainAndCover()
    {
        QFETCH(QString, clientShell);
        QFETCH(bool, lateCover);

        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        QFile::setPermissions(runtime.path(), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        const QString lipstickReport = runtime.filePath(QStringLiteral("lipstick.json"));
        const QString shellReport = runtime.filePath(QStringLiteral("shell.json"));
        const QString clientReport = runtime.filePath(QStringLiteral("client.json"));

        QProcessEnvironment base = QProcessEnvironment::systemEnvironment();
        base.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtime.path());
        base.remove(QStringLiteral("WAYLAND_DISPLAY"));
        base.remove(QStringLiteral("DISPLAY"));
        // The host desktop's session must not reach the apps: on GNOME, Qt
        // 6.10+ loads its GTK 3 platform theme, which aborts on the nested
        // compositor (no wl_shm it can use). Lipstick sets none of these.
        for (const char *var : {"XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION",
                                "QT_QPA_PLATFORMTHEME", "QT_IM_MODULE", "QT_IM_MODULES", "GTK_IM_MODULE"})
            base.remove(QString::fromLatin1(var));

        // 1. fake Lipstick.
        QProcess lipstick;
        QProcessEnvironment lenv = base;
        lenv.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
        lipstick.setProcessEnvironment(lenv);
        lipstick.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        lipstick.start(QStringLiteral(FAKE_LIPSTICK_BIN),
                       QStringList() << "--socket" << "fake-lipstick-0" << "--report" << lipstickReport);
        QVERIFY(lipstick.waitForStarted());
        QTRY_VERIFY_WITH_TIMEOUT(lipstick.canReadLine() || lipstick.waitForReadyRead(100), 10000);
        QVERIFY(QString::fromUtf8(lipstick.readLine()).startsWith(QLatin1String("ready")));

        // 2. keel-shell as a Wayland client of fake Lipstick, launching the app.
        QProcess shell;
        QProcessEnvironment senv = base;
        senv.insert(QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("fake-lipstick-0"));
        senv.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("wayland"));
        // Lipstick speaks wl_shell; qt_extended_surface rides on it.
        senv.insert(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"), QStringLiteral("wl-shell"));
        senv.insert(QStringLiteral("KEEL_SHELL_REPORT"), shellReport);
        shell.setProcessEnvironment(senv);
        shell.setProcessChannelMode(QProcess::ForwardedChannels);
        QStringList args;
        args << "--verbose" << "--dpi" << "401" << "--client-shell" << clientShell
             << "--" << QStringLiteral(TEST_CLIENT_BIN) << "--report" << clientReport;
        if (lateCover)
            args << "--late-cover";
        shell.start(QStringLiteral(KEEL_SHELL_BIN), args);
        QVERIFY(shell.waitForStarted());

        // 3. Wait for two Lipstick surfaces with content, one tagged cover.
        auto coverAndMainReady = [&]() {
            const QJsonArray surfaces = readJson(lipstickReport).value(QStringLiteral("surfaces")).toArray();
            int withContent = 0, covers = 0;
            for (const QJsonValue &v : surfaces) {
                const QJsonObject s = v.toObject();
                if (!s.value(QStringLiteral("hasContent")).toBool())
                    continue;
                ++withContent;
                if (s.value(QStringLiteral("category")).toString() == QLatin1String("cover"))
                    ++covers;
            }
            return withContent == 2 && covers == 1;
        };
        QTRY_VERIFY_WITH_TIMEOUT(coverAndMainReady(), 30000);

        const QJsonArray surfaces = readJson(lipstickReport).value(QStringLiteral("surfaces")).toArray();
        for (const QJsonValue &v : surfaces) {
            const QJsonObject s = v.toObject();
            QVERIFY(s.value(QStringLiteral("extendedSurface")).toBool());   // property came via qt_extended_surface
            QCOMPARE(s.value(QStringLiteral("role")).toString(), QStringLiteral("wl_shell"));
            if (s.value(QStringLiteral("category")).toString() == QLatin1String("cover") && !lateCover) {
                // The Lipstick cover window takes the cover surface's size.
                // (A late cover was first configured as a full-size
                // secondary window, so its size is the client's business.)
                QCOMPARE(s.value(QStringLiteral("width")).toInt(), 234);
                QCOMPARE(s.value(QStringLiteral("height")).toInt(), 374);
            } else if (s.value(QStringLiteral("category")).toString() != QLatin1String("cover")) {
                QVERIFY(!s.value(QStringLiteral("properties")).toObject().contains(QStringLiteral("CATEGORY")));
            }
        }

        // 4. keel-shell's own view of its windows.
        const QJsonObject sr = readJson(shellReport);
        QCOMPARE(sr.value(QStringLiteral("backend")).toString(), QStringLiteral("qt515"));
        QStringList roles;
        for (const auto &v : sr.value(QStringLiteral("windows")).toArray()) {
            const QJsonObject w = v.toObject();
            roles << w.value(QStringLiteral("role")).toString();
            if (w.value(QStringLiteral("role")).toString() == QLatin1String("cover"))
                QCOMPARE(w.value(QStringLiteral("category")).toString(), QStringLiteral("cover"));
        }
        roles.sort();
        QCOMPARE(roles, QStringList() << "cover" << "main");

        // 5. The app saw the Keel environment and reached the peer bus.
        QTRY_VERIFY_WITH_TIMEOUT(readJson(clientReport).value(QStringLiteral("coverExposed")).toBool(), 10000);
        const QJsonObject cr = readJson(clientReport);
        QCOMPARE(cr.value(QStringLiteral("KEEL_SHELL")).toString(), QStringLiteral("1"));
        QCOMPARE(cr.value(QStringLiteral("platform")).toString(), QStringLiteral("wayland"));
        QCOMPARE(cr.value(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION")).toString(), clientShell);
        QCOMPARE(cr.value(QStringLiteral("QT_WAYLAND_FORCE_DPI")).toString(), QStringLiteral("401"));
        QVERIFY(cr.value(QStringLiteral("WAYLAND_DISPLAY")).toString() != QLatin1String("fake-lipstick-0"));
        QVERIFY(cr.value(QStringLiteral("dbusConnected")).toBool());
        QCOMPARE(cr.value(QStringLiteral("ping")).toString(), QStringLiteral("keel-shell"));
        QCOMPARE(cr.value(QStringLiteral("dpi")).toInt(), 401);
        QVERIFY(cr.value(QStringLiteral("mainExposed")).toBool());

        // 6. SIGTERM (what Lipstick sends to close an app) ends app and shell.
        ::kill(static_cast<pid_t>(shell.processId()), SIGTERM);
        QVERIFY(shell.waitForFinished(15000));
        QCOMPARE(shell.exitStatus(), QProcess::NormalExit);

        lipstick.terminate();
        if (!lipstick.waitForFinished(5000))
            lipstick.kill();
    }
};

QTEST_GUILESS_MAIN(TestE2E)
#include "tst_e2e.moc"
