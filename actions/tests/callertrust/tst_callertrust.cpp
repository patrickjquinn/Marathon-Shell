// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keelcallertrust.h: a process is recognised by the file it runs (not by a
// path that merely looks right), by the privileged group, or as the app's
// own process; nothing else, and nothing that cannot be inspected, is
// trusted.

#include "keelcallertrust.h"

#include <QCoreApplication>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include <unistd.h>

class TestCallerTrust : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void theFileCountsNotThePath()
    {
        const qint64 me = QCoreApplication::applicationPid();
        const QString exe = QCoreApplication::applicationFilePath();
        QVERIFY(KeelCallerTrust::runsOneOf(me, {exe}));
        QVERIFY(!KeelCallerTrust::runsOneOf(me, {QStringLiteral("/bin/sh")}));
        QVERIFY(!KeelCallerTrust::runsOneOf(me, {}));

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        // Another name for the same file (a symlink) is the same file.
        const QString link = dir.filePath(QStringLiteral("link"));
        QVERIFY(QFile::link(exe, link));
        QVERIFY(KeelCallerTrust::runsOneOf(me, {QStringLiteral("/nonexistent"), link}));
        // A copy at a path of one's choosing is not.
        const QString copy = dir.filePath(QStringLiteral("copy"));
        QVERIFY(QFile::copy(exe, copy));
        QVERIFY(!KeelCallerTrust::runsOneOf(me, {copy}));
    }

    void processesThatCannotBeInspected()
    {
        const QString exe = QCoreApplication::applicationFilePath();
        QVERIFY(!KeelCallerTrust::runsOneOf(0, {exe}));
        QVERIFY(!KeelCallerTrust::runsOneOf(-1, {exe}));
        QVERIFY(!KeelCallerTrust::runsOneOf(0x7fffffff, {exe}));
        QVERIFY(!KeelCallerTrust::effectiveGid(0x7fffffff));
        QVERIFY(!KeelCallerTrust::isTrusted(0));
        QVERIFY(!KeelCallerTrust::isTrusted(0x7fffffff));
    }

    void effectiveGroup()
    {
        QCOMPARE(KeelCallerTrust::effectiveGid(QCoreApplication::applicationPid()), std::optional<uint>(::getegid()));
    }

    void whoIsTrusted()
    {
        // The app's own process.
        QVERIFY(KeelCallerTrust::isTrusted(QCoreApplication::applicationPid()));
        // The known executables, by file.
        QVERIFY(KeelCallerTrust::trustedExecutables().contains(QStringLiteral("/usr/bin/pilotd")));
        QVERIFY(KeelCallerTrust::trustedExecutables().contains(QStringLiteral("/usr/bin/keel-mcp")));
        // Whoever started this test (ctest, a shell) is none of them, unless
        // it runs in the privileged group.
        const qint64 parent = ::getppid();
        const std::optional<uint> privileged = KeelCallerTrust::privilegedGid();
        const bool parentPrivileged = privileged && KeelCallerTrust::effectiveGid(parent) == privileged;
        QCOMPARE(KeelCallerTrust::isTrusted(parent), parentPrivileged);
    }
};

QTEST_GUILESS_MAIN(TestCallerTrust)
#include "tst_callertrust.moc"
