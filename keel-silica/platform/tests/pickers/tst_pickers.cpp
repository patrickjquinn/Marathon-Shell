// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers models on a fake home directory, and the Tracker 3
// source against a fake Tracker endpoint on a private bus (run under
// dbus-run-session).
//
//   tst_keel_pickers                     the tests
//   tst_keel_pickers --make-fixture DIR  writes the fake home the QML tests
//                                        (tests/pickers/qml) run against

#include "trackersource.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QDBusVirtualObject>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSemaphore>
#include <QTemporaryDir>
#include <QTest>
#include <QThread>
#include <memory>
#include <unistd.h>

using keel::pickers::TrackerSource;

namespace {

QByteArray id3Title(const QByteArray &title)
{
    const QByteArray body = '\x03' + title;
    QByteArray frame = "TIT2";
    const auto n = static_cast<quint32>(body.size());
    frame += static_cast<char>((n >> 21) & 0x7f);
    frame += static_cast<char>((n >> 14) & 0x7f);
    frame += static_cast<char>((n >> 7) & 0x7f);
    frame += static_cast<char>(n & 0x7f);
    frame += QByteArray(2, '\0') + body;
    QByteArray tag("ID3\x04\x00\x00", 6);
    const auto m = static_cast<quint32>(frame.size());
    tag += static_cast<char>((m >> 21) & 0x7f);
    tag += static_cast<char>((m >> 14) & 0x7f);
    tag += static_cast<char>((m >> 7) & 0x7f);
    tag += static_cast<char>(m & 0x7f);
    return tag + frame;
}

bool setAge(const QString &path, int ageHours)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadWrite))
        return false;
    return f.setFileTime(QDateTime::currentDateTime().addSecs(-3600LL * ageHours),
                         QFileDevice::FileModificationTime);
}

bool writeFile(const QString &path, const QByteArray &data, int ageHours)
{
    QDir().mkpath(QFileInfo(path).path());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size())
        return false;
    f.close();
    return setAge(path, ageHours);
}

bool writeImage(const QString &path, int ageHours)
{
    QDir().mkpath(QFileInfo(path).path());
    QImage img(8, 8, QImage::Format_RGB32);
    img.fill(Qt::red);
    return img.save(path) && setAge(path, ageHours);
}

// The fake home: content of every category, a hidden file, cover art in
// Music and a download. Ages make the newest-first order checkable.
bool makeFixture(const QString &home)
{
    bool ok = writeImage(home + QStringLiteral("/Pictures/beach.png"), 1);
    ok = ok && writeImage(home + QStringLiteral("/Pictures/Camera/older.png"), 48);
    ok = ok && writeFile(home + QStringLiteral("/Pictures/.hidden.png"), "x", 1);
    ok = ok && writeFile(home + QStringLiteral("/Music/Album/cover.jpg"), "jpeg", 1);
    ok = ok && writeFile(home + QStringLiteral("/Music/Album/song.mp3"), id3Title("Tagged Song"), 2);
    ok = ok && writeFile(home + QStringLiteral("/Music/untagged.ogg"), "OggS", 3);
    ok = ok && writeFile(home + QStringLiteral("/Videos/clip.mp4"), "mp4", 4);
    ok = ok && writeFile(home + QStringLiteral("/Documents/report.pdf"), "%PDF-1.4", 5);
    ok = ok && writeFile(home + QStringLiteral("/Documents/notes.txt"), "notes", 6);
    ok = ok && writeFile(home + QStringLiteral("/Documents/Sub/deep.odt"), "odt", 7);
    ok = ok && writeFile(home + QStringLiteral("/Downloads/archive.zip"), "PK", 8);
    ok = ok && writeFile(home + QStringLiteral("/Downloads/manual.pdf"), "%PDF", 9);
    ok = ok && writeFile(home + QStringLiteral("/other.bin"), "bin", 10);
    return ok;
}

// ---------------------------------------------------------------------------
// A fake Tracker 3 endpoint: answers Query by writing fixed rows into the
// passed descriptor in the endpoint's format, then replying the names.
// ---------------------------------------------------------------------------

QByteArray cursorRow(const QStringList &values)
{
    QByteArray out;
    auto put = [&out](qint32 v) { out.append(reinterpret_cast<const char *>(&v), sizeof v); };
    put(static_cast<qint32>(values.size()));
    for (qsizetype i = 0; i < values.size(); ++i)
        put(1); // TRACKER_SPARQL_VALUE_TYPE_STRING
    qint32 offset = -1;
    QList<QByteArray> utf8;
    for (const QString &v : values) {
        utf8.append(v.toUtf8());
        offset += static_cast<qint32>(utf8.last().size()) + 1;
        put(offset);
    }
    for (const QByteArray &v : utf8)
        out += v + '\0';
    return out;
}

class FakeTracker : public QDBusVirtualObject
{
public:
    QString lastQuery;
    QList<QStringList> rows;
    int queries = 0;

    QString introspect(const QString &) const override { return {}; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.member() != QLatin1String("Query"))
            return false;
        ++queries;
        lastQuery = message.arguments().value(0).toString();
        const auto fd = qvariant_cast<QDBusUnixFileDescriptor>(message.arguments().value(1));
        QByteArray data;
        for (const QStringList &r : std::as_const(rows))
            data += cursorRow(r);
        // Large enough to need the reader while writing (more than a pipe
        // buffer): the endpoint writes every row before it replies.
        qsizetype written = 0;
        while (written < data.size()) {
            const ssize_t n = ::write(fd.fileDescriptor(), data.constData() + written, data.size() - written);
            if (n <= 0)
                break;
            written += n;
        }
        connection.send(message.createReply(QStringList { QStringLiteral("url"), QStringLiteral("mime"),
                                                          QStringLiteral("title"), QStringLiteral("size"),
                                                          QStringLiteral("modified") }));
        return true;
    }
};

} // namespace

class tst_Pickers : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void contentModel_data();
    void contentModel();
    void contentModelFilters();
    void contentModelSelection();
    void folderModel();
    void cursorFormat();
    void trackerSource();

private:
    QObject *create(const QByteArray &qml);
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_Pickers::initTestCase()
{
    // main() pointed HOME at a temporary directory.
    QVERIFY(makeFixture(QDir::homePath()));
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

QObject *tst_Pickers::create(const QByteArray &qml)
{
    QQmlComponent c(m_engine.get());
    c.setData("import QtQuick 2.0\nimport Sailfish.Pickers 1.0\n" + qml, QUrl(QStringLiteral("inline.qml")));
    QObject *o = c.create();
    if (!o)
        qWarning().noquote() << c.errorString();
    return o;
}

void tst_Pickers::contentModel_data()
{
    QTest::addColumn<QByteArray>("type");
    QTest::addColumn<QStringList>("names");
    // Newest first; hidden files and Music cover art are left out.
    QTest::newRow("images") << QByteArray("ImageContent") << QStringList { "beach.png", "older.png" };
    QTest::newRow("music") << QByteArray("MusicContent") << QStringList { "song.mp3", "untagged.ogg" };
    QTest::newRow("videos") << QByteArray("VideoContent") << QStringList { "clip.mp4" };
    QTest::newRow("documents") << QByteArray("DocumentContent")
                               << QStringList { "report.pdf", "notes.txt", "deep.odt", "manual.pdf" };
    QTest::newRow("downloads") << QByteArray("DownloadContent") << QStringList { "archive.zip", "manual.pdf" };
    QTest::newRow("any") << QByteArray("AnyContent")
                         << QStringList { "beach.png", "song.mp3", "untagged.ogg", "clip.mp4", "report.pdf",
                                          "notes.txt", "deep.odt", "manual.pdf", "older.png" };
}

void tst_Pickers::contentModel()
{
    QFETCH(QByteArray, type);
    QFETCH(QStringList, names);
    std::unique_ptr<QObject> m(create("KeelContentModel { contentType: KeelContentModel." + type + " }"));
    QVERIFY(m);
    QTRY_VERIFY(!m->property("loading").toBool());
    QCOMPARE(m->property("source").toString(), QStringLiteral("filesystem"));
    QStringList got;
    for (int i = 0; i < m->property("count").toInt(); ++i) {
        QVariantMap item;
        QVERIFY(QMetaObject::invokeMethod(m.get(), "get", Q_RETURN_ARG(QVariantMap, item), Q_ARG(int, i)));
        got.append(item.value(QStringLiteral("fileName")).toString());
        // The documented selectedContentProperties members.
        for (const char *key : { "fileName", "filePath", "url", "title", "mimeType" })
            QVERIFY2(item.contains(QLatin1String(key)), key);
        QCOMPARE(item.value(QStringLiteral("url")).toUrl(),
                 QUrl::fromLocalFile(item.value(QStringLiteral("filePath")).toString()));
        if (got.last() == QLatin1String("song.mp3"))
            QCOMPARE(item.value(QStringLiteral("title")).toString(), QStringLiteral("Tagged Song"));
        if (got.last() == QLatin1String("report.pdf")) {
            QCOMPARE(item.value(QStringLiteral("title")).toString(), QStringLiteral("report"));
            QCOMPARE(item.value(QStringLiteral("mimeType")).toString(), QStringLiteral("application/pdf"));
        }
    }
    QCOMPARE(got, names);
}

void tst_Pickers::contentModelFilters()
{
    std::unique_ptr<QObject> m(create("KeelContentModel { contentType: KeelContentModel.FileContent;"
                                      " nameFilters: ['*.PDF', '*.bin'] }"));
    QVERIFY(m);
    QTRY_VERIFY(!m->property("loading").toBool());
    QCOMPARE(m->property("count").toInt(), 3); // report.pdf, manual.pdf, other.bin
    m->setProperty("filter", QStringLiteral("rep"));
    QCOMPARE(m->property("count").toInt(), 1);
    m->setProperty("filter", QString());
    QCOMPARE(m->property("count").toInt(), 3);
}

void tst_Pickers::contentModelSelection()
{
    std::unique_ptr<QObject> m(create("KeelContentModel { contentType: KeelContentModel.DocumentContent }"));
    QVERIFY(m);
    QTRY_VERIFY(!m->property("loading").toBool());
    QVERIFY(QMetaObject::invokeMethod(m.get(), "toggleSelected", Q_ARG(int, 0)));
    QVERIFY(QMetaObject::invokeMethod(m.get(), "setSelected", Q_ARG(int, 2), Q_ARG(bool, true)));
    QCOMPARE(m->property("selectedCount").toInt(), 2);
    QVariantList selected;
    QVERIFY(QMetaObject::invokeMethod(m.get(), "selectedItems", Q_RETURN_ARG(QVariantList, selected)));
    QCOMPARE(selected.size(), 2);
    QCOMPARE(selected.at(1).toMap().value(QStringLiteral("fileName")).toString(), QStringLiteral("deep.odt"));
    QVERIFY(QMetaObject::invokeMethod(m.get(), "clearSelection"));
    QCOMPARE(m->property("selectedCount").toInt(), 0);
}

void tst_Pickers::folderModel()
{
    std::unique_ptr<QObject> m(create("KeelFolderModel { }"));
    QVERIFY(m);
    QCOMPARE(m->property("path").toString(), QDir::homePath());
    QVERIFY(!m->property("canGoUp").toBool()); // not above home without showSystemFiles
    QVariantMap first;
    QVERIFY(QMetaObject::invokeMethod(m.get(), "get", Q_RETURN_ARG(QVariantMap, first), Q_ARG(int, 0)));
    QCOMPARE(first.value(QStringLiteral("fileName")).toString(), QStringLiteral("Documents")); // folders first
    QCOMPARE(m->property("count").toInt(), 6); // 5 folders + other.bin

    m->setProperty("includeFiles", false);
    QCOMPARE(m->property("count").toInt(), 5);
    m->setProperty("path", QDir::homePath() + QStringLiteral("/Pictures"));
    QVERIFY(m->property("canGoUp").toBool());
    QCOMPARE(m->property("parentPath").toString(), QDir::homePath());
    QCOMPARE(m->property("count").toInt(), 1); // Camera
    m->setProperty("includeFiles", true);
    m->setProperty("nameFilters", QStringList { QStringLiteral("*.png") });
    QCOMPARE(m->property("count").toInt(), 2); // Camera/, beach.png (not the hidden file)
    m->setProperty("showSystemFiles", true);
    QCOMPARE(m->property("count").toInt(), 3); // + .hidden.png
    m->setProperty("path", QDir::homePath());
    QVERIFY(m->property("canGoUp").toBool());
}

void tst_Pickers::cursorFormat()
{
    QList<QStringList> rows;
    QString error;
    const QByteArray data = cursorRow({ "file:///a", "", "T" }) + cursorRow({ "x", "yy", "zzz" });
    QVERIFY(TrackerSource::parseCursor(data, &rows, &error));
    QCOMPARE(rows, (QList<QStringList> { { "file:///a", "", "T" }, { "x", "yy", "zzz" } }));
    rows.clear();
    QVERIFY(!TrackerSource::parseCursor(data.left(data.size() - 2), &rows, &error));
    QVERIFY(!error.isEmpty());
    rows.clear();
    QVERIFY(TrackerSource::parseCursor(QByteArray(), &rows, &error));
    QVERIFY(rows.isEmpty());
    // The query names the classes and properties Keel reads.
    const QString q = TrackerSource::queryFor(keel::pickers::Category::Image, 10);
    QVERIFY(q.contains(QLatin1String("nfo:Image")));
    QVERIFY(q.contains(QLatin1String("nie:isStoredAs")));
    QVERIFY(q.contains(QLatin1String("LIMIT 10")));
    QVERIFY(TrackerSource::queryFor(keel::pickers::Category::Download, 10).isEmpty());
}

void tst_Pickers::trackerSource()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    // The fake endpoint on its own connection and thread.
    FakeTracker fake;
    const QString name = TrackerSource::service();
    QThread thread;
    thread.start();
    QObject context;
    context.moveToThread(&thread);
    QSemaphore ready;
    bool registered = false;
    QMetaObject::invokeMethod(
        &context,
        [&]() {
            QDBusConnection c = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                              QStringLiteral("fake-tracker"));
            registered = c.registerVirtualObject(TrackerSource::objectPath(), &fake)
                && c.registerService(name);
            ready.release();
        },
        Qt::QueuedConnection);
    ready.acquire();
    QVERIFY(registered);
    QVERIFY(TrackerSource::available());

    // 600 rows: more than a pipe buffer.
    const QString home = QDir::homePath();
    fake.rows.append({ QUrl::fromLocalFile(home + QStringLiteral("/Pictures/new.jpg")).toString(),
                       QStringLiteral("image/jpeg"), QStringLiteral("Indexed title"), QStringLiteral("2048"),
                       QStringLiteral("2026-09-30T10:00:00Z") });
    fake.rows.append({ QUrl::fromLocalFile(home + QStringLiteral("/Music/Album/cover.jpg")).toString(),
                       QStringLiteral("image/jpeg"), QString(), QStringLiteral("10"),
                       QStringLiteral("2026-09-29T10:00:00Z") });
    fake.rows.append({ QStringLiteral("http://example.org/remote.jpg"), QStringLiteral("image/jpeg"), QString(),
                       QStringLiteral("1"), QStringLiteral("2026-09-28T10:00:00Z") });
    for (int i = 0; i < 600; ++i)
        fake.rows.append({ QUrl::fromLocalFile(home + QStringLiteral("/Pictures/bulk%1.png").arg(i)).toString(),
                           QStringLiteral("image/png"), QString(), QStringLiteral("1"),
                           QStringLiteral("2026-01-01T00:00:00Z") });

    std::unique_ptr<QObject> m(create("KeelContentModel { contentType: KeelContentModel.ImageContent }"));
    QVERIFY(m);
    QTRY_VERIFY_WITH_TIMEOUT(!m->property("loading").toBool(), 10000);
    QCOMPARE(m->property("source").toString(), QStringLiteral("tracker"));
    QCOMPARE(fake.queries, 1);
    QVERIFY(fake.lastQuery.contains(QLatin1String("nfo:Image")));
    // Remote URLs and Music cover art are dropped; newest first.
    QCOMPARE(m->property("count").toInt(), 601);
    QVariantMap item;
    QVERIFY(QMetaObject::invokeMethod(m.get(), "get", Q_RETURN_ARG(QVariantMap, item), Q_ARG(int, 0)));
    QCOMPARE(item.value(QStringLiteral("fileName")).toString(), QStringLiteral("new.jpg"));
    QCOMPARE(item.value(QStringLiteral("title")).toString(), QStringLiteral("Indexed title"));
    QCOMPARE(item.value(QStringLiteral("fileSize")).toLongLong(), 2048);

    // Downloads never come from Tracker.
    std::unique_ptr<QObject> d(create("KeelContentModel { contentType: KeelContentModel.DownloadContent }"));
    QTRY_VERIFY(!d->property("loading").toBool());
    QCOMPARE(d->property("source").toString(), QStringLiteral("filesystem"));
    QCOMPARE(fake.queries, 1);

    // KEEL_PICKERS_TRACKER=0 turns Tracker off.
    qputenv("KEEL_PICKERS_TRACKER", "0");
    std::unique_ptr<QObject> off(create("KeelContentModel { contentType: KeelContentModel.ImageContent }"));
    QTRY_VERIFY(!off->property("loading").toBool());
    QCOMPARE(off->property("source").toString(), QStringLiteral("filesystem"));
    qunsetenv("KEEL_PICKERS_TRACKER");

    QMetaObject::invokeMethod(
        &context, [&]() { QDBusConnection::disconnectFromBus(QStringLiteral("fake-tracker")); },
        Qt::BlockingQueuedConnection);
    thread.quit();
    thread.wait();
}

int main(int argc, char **argv)
{
    if (argc == 3 && qstrcmp(argv[1], "--make-fixture") == 0) {
        QGuiApplication app(argc, argv);
        return makeFixture(QString::fromLocal8Bit(argv[2])) ? 0 : 1;
    }
    // A fake home for the scans; set before the application reads it.
    QTemporaryDir home;
    if (!home.isValid())
        return 1;
    qputenv("HOME", QFile::encodeName(home.path()));
    qunsetenv("XDG_CONFIG_HOME");
    qunsetenv("XDG_MUSIC_DIR");
    qputenv("USER", "keel-test-nobody");
    QGuiApplication app(argc, argv);
    tst_Pickers test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_pickers.moc"
