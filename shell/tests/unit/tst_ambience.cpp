// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include <QtTest>

#include <QTemporaryDir>

#include "core/ambience.h"

using namespace keel;

// Shape of `dconf dump /desktop/jolla/theme/` output. Key names here are
// illustrative; keel-shell forwards whatever keys exist.
static const char *kThemeDump =
    "[/]\n"
    "color_scheme='lightondark'\n"
    "wallpaper_filename='/home/defaultuser/.local/share/ambienced/wallpapers/x.jpg'\n"
    "opacity=0.75\n"
    "version=uint32 3\n"
    "enabled=true\n"
    "\n"
    "[color]\n"
    "highlight='#ff8080'\n"
    "primary=\"#ffffff\"\n"
    "list=['a', 'b']\n"
    "escaped='it\\'s'\n";

class TestAmbience : public QObject
{
    Q_OBJECT
private slots:
    void parseValue_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<QVariant>("expected");
        QTest::newRow("single quoted") << "'abc'" << QVariant(QStringLiteral("abc"));
        QTest::newRow("double quoted") << "\"abc\"" << QVariant(QStringLiteral("abc"));
        QTest::newRow("escape") << R"('a\'b\\c')" << QVariant(QStringLiteral("a'b\\c"));
        QTest::newRow("unicode escape") << "'\\u00e9'" << QVariant(QString(QChar(0xe9)));
        QTest::newRow("true") << "true" << QVariant(true);
        QTest::newRow("false") << "false" << QVariant(false);
        QTest::newRow("int") << "42" << QVariant(static_cast<qlonglong>(42));
        QTest::newRow("typed uint32") << "uint32 7" << QVariant(static_cast<qlonglong>(7));
        QTest::newRow("typed int64") << "int64 -3" << QVariant(static_cast<qlonglong>(-3));
        QTest::newRow("double") << "1.5" << QVariant(1.5);
        QTest::newRow("typed string") << "@s 'x'" << QVariant(QStringLiteral("x"));
        QTest::newRow("array verbatim") << "['a', 'b']" << QVariant(QStringLiteral("['a', 'b']"));
    }
    void parseValue()
    {
        QFETCH(QString, text);
        QFETCH(QVariant, expected);
        const QVariant v = Ambience::parseValue(text);
        QCOMPARE(v.toString(), expected.toString());
        if (expected.type() == QVariant::Bool)
            QCOMPARE(v.type(), QVariant::Bool);
    }

    void parseDump()
    {
        const QVariantMap m = Ambience::parseDump(QStringLiteral("/desktop/jolla/theme/"),
                                                  QString::fromUtf8(kThemeDump));
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/color_scheme")).toString(),
                 QStringLiteral("lightondark"));
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString(),
                 QStringLiteral("#ff8080"));
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/color/primary")).toString(),
                 QStringLiteral("#ffffff"));
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/version")).toLongLong(), 3LL);
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/enabled")).toBool(), true);
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/opacity")).toDouble(), 0.75);
        QCOMPARE(m.value(QStringLiteral("/desktop/jolla/theme/color/escaped")).toString(),
                 QStringLiteral("it's"));
        QCOMPARE(m.size(), 9);

        // Directory without trailing slash, nested group.
        const QVariantMap n = Ambience::parseDump(QStringLiteral("/a"),
                                                  QStringLiteral("[b/c]\nk=1\n"));
        QCOMPARE(n.keys(), QStringList() << QStringLiteral("/a/b/c/k"));
    }

    void envNames()
    {
        const QList<DconfSource> sources = Ambience::defaultSources();
        QCOMPARE(Ambience::envName(sources.at(0), QStringLiteral("/desktop/jolla/theme/color/highlight")),
                 QStringLiteral("KEEL_AMBIENCE_COLOR_HIGHLIGHT"));
        QCOMPARE(Ambience::envName(sources.at(0), QStringLiteral("/desktop/jolla/theme/color_scheme")),
                 QStringLiteral("KEEL_AMBIENCE_COLOR_SCHEME"));
        QCOMPARE(Ambience::envName(sources.at(1), QStringLiteral("/desktop/sailfish/silica/theme_pixel_ratio")),
                 QStringLiteral("KEEL_SILICA_THEME_PIXEL_RATIO"));
        QCOMPARE(Ambience::envName(sources.at(0), QStringLiteral("/desktop/jolla/theme/a-b.c")),
                 QStringLiteral("KEEL_AMBIENCE_A_B_C"));
    }

    void environment()
    {
        const QVariantMap m = Ambience::parseDump(QStringLiteral("/desktop/jolla/theme/"),
                                                  QString::fromUtf8(kThemeDump));
        QProcessEnvironment env;
        Ambience::applyToEnvironment(Ambience::defaultSources(), m, &env);
        QCOMPARE(env.value(QStringLiteral("KEEL_AMBIENCE_COLOR_HIGHLIGHT")), QStringLiteral("#ff8080"));
        QCOMPARE(env.value(QStringLiteral("KEEL_AMBIENCE_ENABLED")), QStringLiteral("true"));
        QCOMPARE(env.value(QStringLiteral("KEEL_AMBIENCE_VERSION")), QStringLiteral("3"));
        QVERIFY(env.value(QStringLiteral("KEEL_AMBIENCE_KEYS"))
                .split(QLatin1Char(':')).contains(QStringLiteral("/desktop/jolla/theme/color/highlight")));
    }

    void monitorWithFakeDconf()
    {
        // A fake `dconf` that serves dumps from files and "watches" by
        // printing a line whenever a trigger file appears.
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString script = dir.filePath(QStringLiteral("dconf"));
        QFile f(script);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QStringLiteral(
            "#!/bin/sh\n"
            "D='%1'\n"
            "case \"$1\" in\n"
            "  dump) case \"$2\" in /desktop/jolla/theme/) cat \"$D/theme\" ;; esac ;;\n"
            "  watch) while [ ! -e \"$D/trigger\" ]; do sleep 0.05; done; echo \"$2color/highlight\"; echo; sleep 30 ;;\n"
            "esac\n").arg(dir.path()).toUtf8());
        f.close();
        QFile::setPermissions(script, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);

        auto writeTheme = [&](const QByteArray &highlight) {
            QFile t(dir.filePath(QStringLiteral("theme")));
            QVERIFY(t.open(QIODevice::WriteOnly));
            t.write("[color]\nhighlight='" + highlight + "'\n");
        };
        writeTheme("#111111");

        QList<DconfSource> sources;
        sources << Ambience::defaultSources().at(0);
        AmbienceMonitor monitor(sources);
        monitor.setDconfProgram(script);
        monitor.refreshNow();
        QCOMPARE(monitor.values().value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString(),
                 QStringLiteral("#111111"));

        QSignalSpy changed(&monitor, &AmbienceMonitor::changed);
        monitor.startWatching();
        writeTheme("#222222");
        QFile trigger(dir.filePath(QStringLiteral("trigger")));
        QVERIFY(trigger.open(QIODevice::WriteOnly));
        trigger.close();
        QVERIFY(changed.wait(5000));
        QCOMPARE(changed.last().at(0).toMap()
                 .value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString(),
                 QStringLiteral("#222222"));
    }

    void refreshDoesNotBlock()
    {
        // A slow `dconf dump` must not stall the compositor's event loop:
        // keel-shell draws the app's frames on this thread.
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString script = dir.filePath(QStringLiteral("dconf"));
        QFile f(script);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QStringLiteral(
            "#!/bin/sh\n"
            "D='%1'\n"
            "[ \"$1\" = dump ] || exit 1\n"
            "[ -e \"$D/slow\" ] && sleep 0.8\n"
            "cat \"$D/theme\"\n").arg(dir.path()).toUtf8());
        f.close();
        QFile::setPermissions(script, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        auto touch = [&](const QString &name, const QByteArray &data) {
            QFile t(dir.filePath(name));
            QVERIFY(t.open(QIODevice::WriteOnly));
            t.write(data);
        };
        touch(QStringLiteral("theme"), "[color]\nhighlight='#111111'\n");

        AmbienceMonitor monitor(Ambience::defaultSources());
        monitor.setDconfProgram(script);
        monitor.refreshNow();
        touch(QStringLiteral("theme"), "[color]\nhighlight='#333333'\n");
        touch(QStringLiteral("slow"), "");

        QSignalSpy changed(&monitor, &AmbienceMonitor::changed);
        QElapsedTimer clock;
        clock.start();
        monitor.refreshAsync();
        // refreshAsync() returns at once...
        QVERIFY2(clock.elapsed() < 400, qPrintable(QString::number(clock.elapsed())));
        // ...and the event loop keeps turning while both dumps run.
        qint64 last = clock.elapsed();
        qint64 maxGap = 0;
        QTimer tick;
        connect(&tick, &QTimer::timeout, [&]() {
            maxGap = qMax(maxGap, clock.elapsed() - last);
            last = clock.elapsed();
        });
        tick.start(10);
        QVERIFY(changed.wait(5000));
        QVERIFY2(maxGap < 400, qPrintable(QString::number(maxGap)));
        QCOMPARE(changed.count(), 1);
        QCOMPARE(monitor.values().value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString(),
                 QStringLiteral("#333333"));
    }

    void failedDumpKeepsValues()
    {
        // A dump that fails (here: the silica directory) keeps that
        // directory's previous values instead of dropping them.
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString script = dir.filePath(QStringLiteral("dconf"));
        QFile f(script);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QStringLiteral(
            "#!/bin/sh\n"
            "D='%1'\n"
            "case \"$2\" in\n"
            "  /desktop/jolla/theme/) cat \"$D/theme\" ;;\n"
            "  *) [ -e \"$D/fail\" ] && exit 1; echo \"[/]\"; echo \"theme_pixel_ratio=1.5\" ;;\n"
            "esac\n").arg(dir.path()).toUtf8());
        f.close();
        QFile::setPermissions(script, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        auto touch = [&](const QString &name, const QByteArray &data) {
            QFile t(dir.filePath(name));
            QVERIFY(t.open(QIODevice::WriteOnly));
            t.write(data);
        };
        touch(QStringLiteral("theme"), "[color]\nhighlight='#111111'\n");

        AmbienceMonitor monitor(Ambience::defaultSources());
        monitor.setDconfProgram(script);
        monitor.refreshNow();
        const QString ratio = QStringLiteral("/desktop/sailfish/silica/theme_pixel_ratio");
        QCOMPARE(monitor.values().value(ratio).toDouble(), 1.5);

        touch(QStringLiteral("theme"), "[color]\nhighlight='#222222'\n");
        touch(QStringLiteral("fail"), "");
        QSignalSpy changed(&monitor, &AmbienceMonitor::changed);
        monitor.refreshAsync();
        QVERIFY(changed.wait(5000));
        QCOMPARE(monitor.values().value(QStringLiteral("/desktop/jolla/theme/color/highlight")).toString(),
                 QStringLiteral("#222222"));
        QCOMPARE(monitor.values().value(ratio).toDouble(), 1.5);
    }

    void monitorWithoutDconf()
    {
        AmbienceMonitor monitor(Ambience::defaultSources());
        monitor.setDconfProgram(QStringLiteral("keel-shell-no-such-dconf-binary"));
        monitor.refreshNow();
        QVERIFY(monitor.values().isEmpty());
        monitor.startWatching();   // warns, does not crash
    }
};

QTEST_GUILESS_MAIN(TestAmbience)
#include "tst_ambience.moc"
