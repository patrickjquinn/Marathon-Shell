#include <QtTest>
#include <QImage>
#include <QTemporaryDir>

#include "Artwork.h"

class TestMusicArtwork : public QObject {
    Q_OBJECT

  private:
    QTemporaryDir m_dir;

  private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        qputenv("XDG_CACHE_HOME", (m_dir.path() + "/cache").toUtf8());
    }

    void cachesEmbeddedArtOncePerTrack() {
        Artwork    art;
        const QUrl track = QUrl::fromLocalFile(m_dir.path() + "/a/1.mp3");
        QImage     image(1000, 500, QImage::Format_RGB32);
        image.fill(Qt::red);
        const QUrl url = art.cache(QVariant::fromValue(image), track);
        QVERIFY(url.isLocalFile());
        QImage saved(url.toLocalFile());
        QCOMPARE(saved.size(), QSize(720, 360));
        QCOMPARE(art.cache(QVariant::fromValue(QImage(10, 10, QImage::Format_RGB32)), track), url);
        QVERIFY(art.cache(QVariant(), track).isEmpty());
        QVERIFY(art.cache(QVariant::fromValue(QImage()), track).isEmpty());
    }

    void findsCoverNextToTheFile() {
        Artwork art;
        QDir().mkpath(m_dir.path() + "/b");
        const QUrl track = QUrl::fromLocalFile(m_dir.path() + "/b/1.mp3");
        QVERIFY(art.folderArt(track).isEmpty());
        QImage(4, 4, QImage::Format_RGB32).save(m_dir.path() + "/b/folder.jpg");
        QCOMPARE(art.folderArt(track), QUrl::fromLocalFile(m_dir.path() + "/b/folder.jpg"));
    }
};

QTEST_GUILESS_MAIN(TestMusicArtwork)
#include "test_musicartwork.moc"
