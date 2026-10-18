#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include "musiclibrarymanager.h"

class TestMusicLibrary : public QObject {
    Q_OBJECT

  private:
    QTemporaryDir m_home;
    QString       m_music;

    void          touch(const QString &relative) {
        const QString path = m_music + "/" + relative;
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
    }

    static QVariantList load(MusicLibraryManager &library) {
        QSignalSpy loaded(&library, &MusicLibraryManager::tracksLoaded);
        library.loadTracksAsync();
        if (!loaded.wait(5000))
            return {};
        return loaded.takeFirst().at(0).toList();
    }

    static void scan(MusicLibraryManager &library) {
        QSignalSpy done(&library, &MusicLibraryManager::scanComplete);
        library.scanLibraryAsync();
        QVERIFY(done.wait(5000));
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_home.isValid());
        qputenv("HOME", m_home.path().toUtf8());
        qputenv("XDG_CONFIG_HOME", (m_home.path() + "/config").toUtf8());
        qputenv("XDG_DATA_HOME", (m_home.path() + "/data").toUtf8());
        m_music = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
        QVERIFY(m_music.startsWith(m_home.path()));
    }

    void scanStoresTracksOffTheGuiThread() {
        touch("Ava/Sky/Blue.mp3");
        touch("Bo/Ice/Cold.flac");
        touch("Bo/Ice/notes.txt");
        MusicLibraryManager library;
        QSignalSpy          progress(&library, &MusicLibraryManager::scanProgressChanged);
        scan(library);
        QCOMPARE(library.trackCount(), 2);
        QCOMPARE(library.scanProgress(), 100);
        QCOMPARE(library.artists().size(), 2);

        const QVariantList tracks = load(library);
        QCOMPARE(tracks.size(), 2);
        QCOMPARE(tracks.at(0).toMap().value("title").toString(), QStringLiteral("Blue"));
        QCOMPARE(tracks.at(0).toMap().value("artist").toString(), QStringLiteral("Ava"));
        QVERIFY(tracks.at(0).toMap().value("path").toString().startsWith("file://"));
    }

    void rescanKeepsIdsAndDropsDeletedFiles() {
        MusicLibraryManager library;
        const QVariantList  before = load(library);
        QCOMPARE(before.size(), 2);
        QVERIFY(QFile::remove(m_music + "/Ava/Sky/Blue.mp3"));
        touch("Cy/Sun/Dawn.ogg");
        scan(library);
        const QVariantList after = load(library);
        QCOMPARE(after.size(), 2);
        QStringList titles;
        for (const QVariant &t : after)
            titles << t.toMap().value("title").toString();
        QCOMPARE(titles, (QStringList{"Cold", "Dawn"}));
        QCOMPARE(after.at(0).toMap().value("id"), before.at(1).toMap().value("id"));
    }

    void largeLibraryReportsBatches() {
        for (int i = 0; i < 450; ++i)
            touch(QStringLiteral("Many/Album/%1.mp3").arg(i));
        MusicLibraryManager library;
        QSignalSpy          changed(&library, &MusicLibraryManager::libraryChanged);
        scan(library);
        QVERIFY(changed.size() >= 3);
        QCOMPARE(library.trackCount(), 452);
    }
};

QTEST_GUILESS_MAIN(TestMusicLibrary)
#include "test_musiclibrary.moc"
