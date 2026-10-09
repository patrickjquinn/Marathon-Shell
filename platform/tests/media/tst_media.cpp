// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media on the offscreen platform: MediaKey takes its key before
// the focused item, reports press, repeat and release, and keeps the
// GRABBED_KEYS property (decimal Qt key codes, as Lipstick reads it) on the
// app's windows; MetadataReader reads title tags; the QML types load on
// Keel's Silica.

#include "tagreader.h"

#include <QFile>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>
#include <memory>

class tst_Media : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void mediaKeyTakesItsKey();
    void mediaKeyWindowProperty();
    void mediaKeyDisabled();
    void metadataTitles();
    void qmlTypes();

private:
    static QStringList grabbed(const QWindow *w) { return w->property("GRABBED_KEYS").toStringList(); }
    static void sendKey(QWindow *w, QEvent::Type type, int key, bool autoRepeat = false)
    {
        QKeyEvent e(type, key, Qt::NoModifier, QString(), autoRepeat);
        QCoreApplication::sendEvent(w, &e);
    }
    QObject *createObject(const QByteArray &qml);

    QTemporaryDir m_dir;
    std::unique_ptr<QQmlEngine> m_engine;
};

void tst_Media::initTestCase()
{
    QVERIFY(m_dir.isValid());
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

QObject *tst_Media::createObject(const QByteArray &qml)
{
    QQmlComponent c(m_engine.get());
    c.setData(qml, QUrl(QStringLiteral("inline.qml")));
    QObject *o = c.create();
    if (!o)
        qWarning().noquote() << c.errorString();
    return o;
}

static const char kKeysQml[] = R"QML(
import QtQuick 2.0
import Sailfish.Media 1.0
Item {
    id: root
    width: 100; height: 100
    focus: true
    property int itemKeys
    property int presses
    property int releases
    property int repeats
    property alias volumeUp: up
    property alias play: play
    Keys.onPressed: itemKeys++
    MediaKey {
        id: up
        key: Qt.Key_VolumeUp
        onPressed: root.presses++
        onReleased: root.releases++
        onRepeat: root.repeats++
    }
    MediaKey {
        // A second MediaKey for the same key also hears it.
        key: Qt.Key_VolumeUp
        onPressed: root.presses += 100
    }
    MediaKey {
        id: play
        key: Qt.Key_MediaPlay
        enabled: false
    }
}
)QML";

void tst_Media::mediaKeyTakesItsKey()
{
    QQuickView view(m_engine.get(), nullptr);
    QQmlComponent c(m_engine.get());
    c.setData(kKeysQml, QUrl(QStringLiteral("keys.qml")));
    std::unique_ptr<QObject> root(c.create());
    QVERIFY2(root, qPrintable(c.errorString()));
    auto *item = qobject_cast<QQuickItem *>(root.get());
    item->setParentItem(view.contentItem());
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    item->forceActiveFocus();
    auto *up = root->property("volumeUp").value<QObject *>();
    QVERIFY(up);

    sendKey(&view, QEvent::KeyPress, Qt::Key_VolumeUp);
    QCOMPARE(root->property("presses").toInt(), 101);
    QVERIFY(up->property("pressed").toBool());
    QCOMPARE(root->property("itemKeys").toInt(), 0); // taken before the focused item

    // Auto-repeat (client-side keyboard repeat): KeyRelease+KeyPress pairs
    // flagged autoRepeat; each press is one repeat(), releases are ignored.
    for (int i = 0; i < 3; ++i) {
        sendKey(&view, QEvent::KeyRelease, Qt::Key_VolumeUp, true);
        sendKey(&view, QEvent::KeyPress, Qt::Key_VolumeUp, true);
    }
    QCOMPARE(root->property("repeats").toInt(), 3);
    QCOMPARE(root->property("releases").toInt(), 0);
    QVERIFY(up->property("pressed").toBool());

    sendKey(&view, QEvent::KeyRelease, Qt::Key_VolumeUp);
    QCOMPARE(root->property("releases").toInt(), 1);
    QVERIFY(!up->property("pressed").toBool());
    QCOMPARE(root->property("itemKeys").toInt(), 0);

    // Other keys, and keys of disabled MediaKeys, reach the item.
    sendKey(&view, QEvent::KeyPress, Qt::Key_A);
    sendKey(&view, QEvent::KeyPress, Qt::Key_MediaPlay);
    QCOMPARE(root->property("itemKeys").toInt(), 2);
    QCOMPARE(root->property("presses").toInt(), 101);
}

void tst_Media::mediaKeyWindowProperty()
{
    QQuickView view(m_engine.get(), nullptr);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    QCOMPARE(grabbed(&view), QStringList());

    QQmlComponent c(m_engine.get());
    c.setData(kKeysQml, QUrl(QStringLiteral("keys.qml")));
    std::unique_ptr<QObject> root(c.create());
    QVERIFY2(root, qPrintable(c.errorString()));
    // Existing windows get the grab: Qt::Key_VolumeUp only (the MediaPlay
    // MediaKey is disabled), as Lipstick expects it.
    QCOMPARE(grabbed(&view), QStringList { QString::number(Qt::Key_VolumeUp) });

    auto *play = root->property("play").value<QObject *>();
    play->setProperty("enabled", true);
    QCOMPARE(grabbed(&view),
             (QStringList { QString::number(Qt::Key_VolumeUp), QString::number(Qt::Key_MediaPlay) }));

    // A window created later gets it when its platform surface appears.
    QQuickWindow later;
    QCOMPARE(grabbed(&later), QStringList());
    later.show();
    QVERIFY(QTest::qWaitForWindowExposed(&later));
    QCOMPARE(grabbed(&later), grabbed(&view));

    // Destroying the MediaKeys releases the keys.
    root.reset();
    QCOMPARE(grabbed(&view), QStringList());
    QCOMPARE(grabbed(&later), QStringList());
}

void tst_Media::mediaKeyDisabled()
{
    QQuickView view(m_engine.get(), nullptr);
    QQmlComponent c(m_engine.get());
    c.setData(kKeysQml, QUrl(QStringLiteral("keys.qml")));
    std::unique_ptr<QObject> root(c.create());
    QVERIFY2(root, qPrintable(c.errorString()));
    auto *item = qobject_cast<QQuickItem *>(root.get());
    item->setParentItem(view.contentItem());
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    item->forceActiveFocus();

    auto *up = root->property("volumeUp").value<QObject *>();
    sendKey(&view, QEvent::KeyPress, Qt::Key_VolumeUp);
    QVERIFY(up->property("pressed").toBool());
    // Disabling a pressed MediaKey drops `pressed` without a release.
    up->setProperty("enabled", false);
    QVERIFY(!up->property("pressed").toBool());
    QCOMPARE(root->property("releases").toInt(), 0);
    // The other VolumeUp MediaKey still grabs it.
    QCOMPARE(grabbed(&view), QStringList { QString::number(Qt::Key_VolumeUp) });
    sendKey(&view, QEvent::KeyRelease, Qt::Key_VolumeUp);
    QCOMPARE(root->property("releases").toInt(), 0);
    QCOMPARE(root->property("itemKeys").toInt(), 0);
}

namespace {

QByteArray be32(quint32 v)
{
    QByteArray b(4, '\0');
    b[0] = static_cast<char>(v >> 24);
    b[1] = static_cast<char>(v >> 16);
    b[2] = static_cast<char>(v >> 8);
    b[3] = static_cast<char>(v);
    return b;
}

QByteArray le32(quint32 v)
{
    QByteArray b(4, '\0');
    b[0] = static_cast<char>(v);
    b[1] = static_cast<char>(v >> 8);
    b[2] = static_cast<char>(v >> 16);
    b[3] = static_cast<char>(v >> 24);
    return b;
}

QByteArray syncsafe(quint32 v)
{
    QByteArray b(4, '\0');
    b[0] = static_cast<char>((v >> 21) & 0x7f);
    b[1] = static_cast<char>((v >> 14) & 0x7f);
    b[2] = static_cast<char>((v >> 7) & 0x7f);
    b[3] = static_cast<char>(v & 0x7f);
    return b;
}

QByteArray vorbisComment(const QList<QByteArray> &entries)
{
    QByteArray b = le32(4) + "keel";
    b += le32(static_cast<quint32>(entries.size()));
    for (const QByteArray &e : entries)
        b += le32(static_cast<quint32>(e.size())) + e;
    return b;
}

} // namespace

void tst_Media::metadataTitles()
{
    auto write = [this](const QString &name, const QByteArray &data) {
        QFile f(m_dir.filePath(name));
        if (!f.open(QIODevice::WriteOnly))
            return QString();
        f.write(data);
        return f.fileName();
    };
    // ID3v2.3, TIT2 in UTF-16 with BOM, behind another frame.
    QByteArray utf16("\xff\xfe", 2);
    for (QChar ch : QStringLiteral("Säkkijärven polkka"))
        utf16 += QByteArray(reinterpret_cast<const char *>(&ch), 2);
    QByteArray frames = QByteArray("TPE1") + be32(5) + QByteArray(2, '\0') + QByteArray("\x00Kul", 4) + "a";
    frames += QByteArray("TIT2") + be32(static_cast<quint32>(utf16.size() + 1)) + QByteArray(2, '\0') + '\x01' + utf16;
    const QString v23 = write(QStringLiteral("a.mp3"),
                              QByteArray("ID3\x03\x00\x00", 6) + syncsafe(static_cast<quint32>(frames.size())) + frames
                                  + QByteArray(64, '\xff'));
    // ID3v2.4, UTF-8, syncsafe frame size.
    const QByteArray t = QByteArray("\x03") + "Täti Monika";
    const QByteArray f24 = QByteArray("TIT2") + syncsafe(static_cast<quint32>(t.size())) + QByteArray(2, '\0') + t;
    const QString v24
        = write(QStringLiteral("b.mp3"), QByteArray("ID3\x04\x00\x00", 6) + syncsafe(static_cast<quint32>(f24.size())) + f24);
    // ID3v1 only.
    QByteArray v1tag = "TAG" + QByteArray("Old Song").leftJustified(30, '\0') + QByteArray(95, '\0');
    const QString v1 = write(QStringLiteral("c.mp3"), QByteArray(500, '\xff') + v1tag);
    // FLAC: STREAMINFO, then VORBIS_COMMENT as the last block.
    const QByteArray vc = vorbisComment({ "ARTIST=Someone", "title=Flac Title" });
    QByteArray flac = "fLaC";
    flac += QByteArray("\x00", 1) + QByteArray("\x00\x00\x22", 3) + QByteArray(34, '\0');
    flac += static_cast<char>(0x84) + QByteArray(1, static_cast<char>(vc.size() >> 16)) + QByteArray(1, static_cast<char>(vc.size() >> 8))
        + QByteArray(1, static_cast<char>(vc.size())) + vc;
    const QString fl = write(QStringLiteral("d.flac"), flac);
    // Ogg Vorbis and Opus comment packets.
    const QString ogg = write(QStringLiteral("e.ogg"),
                              QByteArray("OggS") + QByteArray(60, '\0') + "\x03vorbis"
                                  + vorbisComment({ "TITLE=Ogg Title" }));
    const QString opus = write(QStringLiteral("f.opus"),
                               QByteArray("OggS") + QByteArray(60, '\0') + "OpusTags"
                                   + vorbisComment({ "TITLE=Opus Title" }));
    const QString none = write(QStringLiteral("My Recording.wav"), QByteArray(100, 'x'));

    QCOMPARE(keel::readTitleTag(v23), QStringLiteral("Säkkijärven polkka"));
    QCOMPARE(keel::readTitleTag(v24), QStringLiteral("Täti Monika"));
    QCOMPARE(keel::readTitleTag(v1), QStringLiteral("Old Song"));
    QCOMPARE(keel::readTitleTag(fl), QStringLiteral("Flac Title"));
    QCOMPARE(keel::readTitleTag(ogg), QStringLiteral("Ogg Title"));
    QCOMPARE(keel::readTitleTag(opus), QStringLiteral("Opus Title"));
    QCOMPARE(keel::readTitleTag(none), QString());
    QCOMPARE(keel::readTitleTag(m_dir.filePath(QStringLiteral("missing.mp3"))), QString());

    // Through QML: tag title, else the file name without extension.
    std::unique_ptr<QObject> reader(createObject("import Sailfish.Media 1.0\nMetadataReader { }"));
    QVERIFY(reader);
    QString title;
    QVERIFY(QMetaObject::invokeMethod(reader.get(), "getTitle", Q_RETURN_ARG(QString, title),
                                      Q_ARG(QUrl, QUrl::fromLocalFile(v24))));
    QCOMPARE(title, QStringLiteral("Täti Monika"));
    QVERIFY(QMetaObject::invokeMethod(reader.get(), "getTitle", Q_RETURN_ARG(QString, title),
                                      Q_ARG(QUrl, QUrl::fromLocalFile(none))));
    QCOMPARE(title, QStringLiteral("My Recording"));
}

void tst_Media::qmlTypes()
{
    std::unique_ptr<QObject> o(createObject(R"QML(
import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Media 1.0
Item {
    width: 540; height: 960
    property int repeatTrack: MediaPlayerControls.RepeatTrack
    property int shufflePlaylists: MediaPlayerControls.ShufflePlaylists
    property alias item: listItem
    property alias panel: panel
    property int clicks
    MediaListItem { id: listItem; width: parent.width; title: "Song"; subtitle: "Artist"; duration: 75; playing: true }
    MediaPlayerControlsPanel {
        id: panel
        duration: 200000; position: 5000
        repeat: MediaPlayerControls.RepeatTrack
        onPlayPauseClicked: clicks++
    }
    MediaPlayerPanelBackground { width: 10; height: 10 }
}
)QML"));
    QVERIFY(o);
    QCOMPARE(o->property("repeatTrack").toInt(), 1);
    QCOMPARE(o->property("shufflePlaylists").toInt(), 2);
    auto *panel = o->property("panel").value<QObject *>();
    QVERIFY(QMetaObject::invokeMethod(panel, "hideControls"));
    QVERIFY(!panel->property("open").toBool());
    QVERIFY(QMetaObject::invokeMethod(panel, "showControls"));
    QVERIFY(panel->property("open").toBool());
    QVERIFY(QMetaObject::invokeMethod(panel, "playPauseClicked"));
    QCOMPARE(o->property("clicks").toInt(), 1);
    QVERIFY(o->property("item").value<QObject *>()->property("contentHeight").toReal() > 0);

    // Every member the public documentation lists (sailfishos.org,
    // sailfish-media: MediaPlayerControlsPanel, MediaListItem, MediaKey).
    auto hasMember = [](const QObject *object, const char *name) {
        const QMetaObject *mo = object->metaObject();
        if (mo->indexOfProperty(name) >= 0)
            return true;
        for (int i = 0; i < mo->methodCount(); ++i) {
            if (mo->method(i).name() == name)
                return true;
        }
        return false;
    };
    for (const char *name : { "active", "duration", "durationScalar", "extraContentItem", "forwardEnabled",
                              "playing", "position", "repeat", "showAddToPlaylist", "showMenu", "shuffle",
                              "addToPlaylist", "nextClicked", "playPauseClicked", "previousClicked", "repeatClicked",
                              "shuffleClicked", "sliderReleased", "hideControls", "hideMenu", "showControls" })
        QVERIFY2(hasMember(panel, name), name);
    const QObject *listItem = o->property("item").value<QObject *>();
    for (const char *name : { "duration", "playing", "subtitle", "subtitleTextFormat", "textFormat", "title" })
        QVERIFY2(hasMember(listItem, name), name);
}

QTEST_MAIN(tst_Media)
#include "tst_media.moc"
