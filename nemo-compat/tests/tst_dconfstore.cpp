// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// KeelDConfStore, the host fallback behind Nemo.Configuration: an unreadable
// file is never overwritten, and failed writes are reported.

#include <QtTest>

#include <QTemporaryDir>

#include "keeldconfstore.h"

class tst_DConfStore : public QObject
{
    Q_OBJECT
private slots:
    void roundTrip();
    void unreadableFileIsBackedUp_data();
    void unreadableFileIsBackedUp();
    void secondBackupDoesNotReplaceFirst();
    void externalCorruptionKeepsValues();
    void failedSyncIsReported();
};

static QByteArray readFile(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

static int s_parseWarnings = 0;

static void countParseWarnings(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    if (type == QtWarningMsg && msg.contains(QLatin1String("cannot parse")))
        ++s_parseWarnings;
}

static void writeFile(const QString &path, const QByteArray &data)
{
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QCOMPARE(f.write(data), data.size());
}

void tst_DConfStore::roundTrip()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString file = dir.filePath(QStringLiteral("dconf.json"));
    {
        KeelDConfStore store(file);
        QVERIFY(store.write(QStringLiteral("/apps/x/a"), 5));
        QVERIFY(store.write(QStringLiteral("/apps/x/b"), QStringLiteral("text")));
    }
    KeelDConfStore again(file);
    QCOMPARE(again.read(QStringLiteral("/apps/x/a")), QVariant(5));
    QCOMPARE(again.read(QStringLiteral("/apps/x/b")), QVariant(QStringLiteral("text")));
    QVERIFY(again.corruptBackup().isEmpty());
}

void tst_DConfStore::unreadableFileIsBackedUp_data()
{
    QTest::addColumn<QByteArray>("contents");
    QTest::newRow("truncated") << QByteArray(R"({"/apps/x/a": 5, "/apps/x/b": )");
    QTest::newRow("not an object") << QByteArray("[1, 2, 3]");
    QTest::newRow("binary") << QByteArray("\x00\xff\x13garbage", 10);
}

void tst_DConfStore::unreadableFileIsBackedUp()
{
    QFETCH(QByteArray, contents);
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString file = dir.filePath(QStringLiteral("dconf.json"));
    writeFile(file, contents);

    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("cannot parse")));
    KeelDConfStore store(file);
    QVERIFY(!store.read(QStringLiteral("/apps/x/a")).isValid());
    // Reading alone leaves the file alone.
    QCOMPARE(readFile(file), contents);

    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("moved the unreadable")));
    QVERIFY(store.write(QStringLiteral("/apps/x/c"), true));
    const QString backup = file + QStringLiteral(".corrupt");
    QCOMPARE(store.corruptBackup(), backup);
    QCOMPARE(readFile(backup), contents);

    KeelDConfStore reread(file);
    QCOMPARE(reread.read(QStringLiteral("/apps/x/c")), QVariant(true));
}

void tst_DConfStore::secondBackupDoesNotReplaceFirst()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString file = dir.filePath(QStringLiteral("dconf.json"));
    writeFile(file + QStringLiteral(".corrupt"), "first");
    writeFile(file, "second {");

    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("cannot parse")));
    KeelDConfStore store(file);
    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("moved the unreadable")));
    QVERIFY(store.write(QStringLiteral("/k"), 1));
    QCOMPARE(readFile(file + QStringLiteral(".corrupt")), QByteArray("first"));
    QCOMPARE(store.corruptBackup(), file + QStringLiteral(".corrupt.1"));
    QCOMPARE(readFile(file + QStringLiteral(".corrupt.1")), QByteArray("second {"));
}

void tst_DConfStore::externalCorruptionKeepsValues()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString file = dir.filePath(QStringLiteral("dconf.json"));
    KeelDConfStore store(file);
    QVERIFY(store.write(QStringLiteral("/apps/x/a"), 1));
    QVERIFY(store.write(QStringLiteral("/apps/x/b"), 2));

    // Another process leaves an unparsable file behind. Wait until the
    // store's file watch has seen it (it logs a parse warning).
    s_parseWarnings = 0;
    const QtMessageHandler previous = qInstallMessageHandler(countParseWarnings);
    writeFile(file, "{ broken");
    QTRY_VERIFY_WITH_TIMEOUT(s_parseWarnings > 0, 5000);
    qInstallMessageHandler(previous);
    // Nothing was lost in memory, and the file was not touched yet.
    QCOMPARE(store.read(QStringLiteral("/apps/x/a")), QVariant(1));
    QCOMPARE(readFile(file), QByteArray("{ broken"));

    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("moved the unreadable")));
    QVERIFY(store.write(QStringLiteral("/apps/x/c"), 3));
    QCOMPARE(readFile(store.corruptBackup()), QByteArray("{ broken"));
    KeelDConfStore reread(file);
    QCOMPARE(reread.read(QStringLiteral("/apps/x/a")), QVariant(1));
    QCOMPARE(reread.read(QStringLiteral("/apps/x/b")), QVariant(2));
    QCOMPARE(reread.read(QStringLiteral("/apps/x/c")), QVariant(3));
}

void tst_DConfStore::failedSyncIsReported()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    // The store's directory is a regular file, so it cannot be created even
    // by root.
    const QString blocker = dir.filePath(QStringLiteral("blocker"));
    writeFile(blocker, "x");
    const QString file = blocker + QStringLiteral("/dconf.json");

    KeelDConfStore store(file);
    QSignalSpy changed(&store, &KeelDConfStore::keyChanged);
    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("cannot create")));
    QVERIFY(!store.write(QStringLiteral("/apps/x/a"), 7));
    // Kept in memory, so this process still sees it and a later sync retries.
    QCOMPARE(store.read(QStringLiteral("/apps/x/a")), QVariant(7));
    QCOMPARE(changed.count(), 1);

    QTest::ignoreMessage(QtWarningMsg, QRegularExpression(QStringLiteral("cannot create")));
    QVERIFY(!store.clear(QStringLiteral("/apps/")));
    QVERIFY(!store.read(QStringLiteral("/apps/x/a")).isValid());

    QFile::remove(blocker);
    QVERIFY(store.write(QStringLiteral("/apps/x/b"), 8));
    QVERIFY(QFileInfo::exists(file));
}

QTEST_GUILESS_MAIN(tst_DConfStore)
#include "tst_dconfstore.moc"
