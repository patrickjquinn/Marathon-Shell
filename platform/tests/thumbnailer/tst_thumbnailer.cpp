// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Nemo.Thumbnailer (nemo-qml-plugin-thumbnailer for Qt 6), offscreen with a
// private cache directory: a Thumbnail item shows a scaled image (fit and
// crop), its file lands in the shared thumbnail cache and is served from
// there again; EXIF orientation is applied; image://nemoThumbnail answers at
// the requested size; a video without the system's thumbnaild-video helper
// (absent on the host) ends in Thumbnail.Error rather than hanging.

#include <QDir>
#include <QDirIterator>
#include <QGuiApplication>
#include <QImageWriter>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickItem>
#include <QQuickView>
#include <QTemporaryDir>
#include <QTest>
#include <memory>

namespace {
// JPEG thumbnails (the cache's format) and scaling shift colours a little.
bool near(const QColor &a, const QColor &b)
{
    return qAbs(a.red() - b.red()) < 40 && qAbs(a.green() - b.green()) < 40 && qAbs(a.blue() - b.blue()) < 40;
}
} // namespace

class tst_Thumbnailer : public QObject
{
    Q_OBJECT

public:
    // The cache is $XDG_CACHE_HOME/org.nemomobile/thumbnails, as upstream:
    // a private one, set before anything reads it.
    tst_Thumbnailer() { qputenv("XDG_CACHE_HOME", QFile::encodeName(m_dir.path() + QStringLiteral("/cache"))); }

private slots:
    void initTestCase();
    void thumbnailItem();
    void imageProvider();
    void videoWithoutHelper();

private:
    QString cacheFiles() const;
    QTemporaryDir m_dir;
    QString m_landscape;
    QString m_rotated;
};

void tst_Thumbnailer::initTestCase()
{
    QVERIFY(m_dir.isValid());

    // 400x200: red left half, blue right half.
    QImage landscape(400, 200, QImage::Format_RGB32);
    landscape.fill(Qt::red);
    for (int y = 0; y < 200; ++y)
        for (int x = 200; x < 400; ++x)
            landscape.setPixel(x, y, qRgb(0, 0, 255));
    m_landscape = m_dir.filePath(QStringLiteral("landscape.png"));
    QVERIFY(landscape.save(m_landscape));

    // The same pixels as a JPEG whose EXIF orientation says "rotate 90".
    m_rotated = m_dir.filePath(QStringLiteral("rotated.jpg"));
    QImageWriter writer(m_rotated, "jpeg");
    writer.setTransformation(QImageIOHandler::TransformationRotate90);
    QVERIFY2(writer.write(landscape), qPrintable(writer.errorString()));
}

QString tst_Thumbnailer::cacheFiles() const
{
    QStringList files;
    QDirIterator it(m_dir.path() + QStringLiteral("/cache/org.nemomobile/thumbnails"), QDir::Files,
                    QDirIterator::Subdirectories);
    while (it.hasNext())
        files << it.next();
    return files.join(QLatin1Char(','));
}

void tst_Thumbnailer::thumbnailItem()
{
    QQuickView view;
    view.engine()->addImportPath(QStringLiteral(KEEL_QML_DIR));
    view.setInitialProperties({ { QStringLiteral("landscape"), QUrl::fromLocalFile(m_landscape) },
                                { QStringLiteral("rotated"), QUrl::fromLocalFile(m_rotated) } });
    view.setSource(QUrl::fromLocalFile(QFINDTESTDATA("thumbnails.qml")));
    QVERIFY2(view.status() == QQuickView::Ready, qPrintable(view.errors().value(0).toString()));
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));

    QQuickItem *root = view.rootObject();
    for (const char *name : { "fit", "crop", "rotatedFit" }) {
        auto *item = root->findChild<QQuickItem *>(QLatin1String(name));
        QVERIFY(item);
        QTRY_COMPARE_WITH_TIMEOUT(item->property("status").toInt(), 1, 10000); // Thumbnail.Ready
    }
    QVERIFY(!cacheFiles().isEmpty());

    // The items show their thumbnails on a frame after Ready.
    QTRY_COMPARE(view.grabWindow().pixelColor(10, 50), QColor(Qt::red));
    const QImage shot = view.grabWindow();
    // "fit" (0,0 100x100): the 400x200 image is 100x50, centred.
    QCOMPARE(shot.pixelColor(10, 50), QColor(Qt::red));
    QCOMPARE(shot.pixelColor(90, 50), QColor(Qt::blue));
    QCOMPARE(shot.pixelColor(50, 10), QColor(Qt::white)); // above the picture
    // "crop" (100,0 100x100): filled, the middle of the image (red | blue).
    QCOMPARE(shot.pixelColor(110, 10), QColor(Qt::red));
    QCOMPARE(shot.pixelColor(190, 90), QColor(Qt::blue));
    // "rotatedFit" (200,0 100x100): turned upright, 50x100, red above blue
    // (rotated 90 degrees clockwise: the left half goes to the top).
    QVERIFY2(near(shot.pixelColor(250, 20), Qt::red), qPrintable(shot.pixelColor(250, 20).name()));
    QVERIFY2(near(shot.pixelColor(250, 80), Qt::blue), qPrintable(shot.pixelColor(250, 80).name()));
    QVERIFY2(near(shot.pixelColor(210, 50), Qt::white), qPrintable(shot.pixelColor(210, 50).name()));
}

void tst_Thumbnailer::imageProvider()
{
    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    // Importing the module installs the provider (initializeEngine).
    QQmlComponent c(&engine);
    c.setData("import QtQuick 2.0\nimport Nemo.Thumbnailer 1.0\nItem {}", QUrl());
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    auto *provider = static_cast<QQuickImageProvider *>(engine.imageProvider(QStringLiteral("nemoThumbnail")));
    QVERIFY(provider);
    QCOMPARE(provider->imageType(), QQmlImageProviderBase::Image);
    QSize size;
    const QImage image = provider->requestImage(m_landscape, &size, QSize(64, 64));
    // The provider crops to a square of the cache's size step at or above the
    // request (Image scales it down), and reports the requested size.
    QCOMPARE(size, QSize(64, 64));
    QVERIFY2(image.width() >= 64 && image.width() == image.height(), qPrintable(QString::number(image.width())));
    QVERIFY(near(image.pixelColor(5, image.height() / 2), Qt::red));
    QVERIFY(near(image.pixelColor(image.width() - 5, image.height() / 2), Qt::blue));
    // Served again from the cache once the original is gone.
    const QString copy = m_dir.filePath(QStringLiteral("copy.png"));
    QVERIFY(QFile::copy(m_landscape, copy));
    QVERIFY(!provider->requestImage(copy, &size, QSize(32, 32)).isNull());
    QVERIFY(QFile::remove(copy));
    QVERIFY(!provider->requestImage(copy, &size, QSize(32, 32)).isNull());
}

void tst_Thumbnailer::videoWithoutHelper()
{
    if (QFile::exists(QStringLiteral("/usr/bin/thumbnaild-video")))
        QSKIP("thumbnaild-video is installed here");
    const QString video = m_dir.filePath(QStringLiteral("clip.mp4"));
    QFile f(video);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("not really a video");
    f.close();

    QQuickView view;
    view.engine()->addImportPath(QStringLiteral(KEEL_QML_DIR));
    view.setInitialProperties({ { QStringLiteral("landscape"), QUrl::fromLocalFile(video) },
                                { QStringLiteral("rotated"), QUrl::fromLocalFile(m_rotated) } });
    view.setSource(QUrl::fromLocalFile(QFINDTESTDATA("thumbnails.qml")));
    QVERIFY(view.status() == QQuickView::Ready);
    view.rootObject()->findChild<QQuickItem *>(QStringLiteral("fit"))->setProperty("mimeType", QStringLiteral("video/mp4"));
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *fit = view.rootObject()->findChild<QQuickItem *>(QStringLiteral("fit"));
    QTRY_COMPARE_WITH_TIMEOUT(fit->property("status").toInt(), 3, 10000); // Thumbnail.Error
}

int main(int argc, char **argv)
{
    tst_Thumbnailer test;
    QGuiApplication app(argc, argv);
    return QTest::qExec(&test, argc, argv);
}

#include "tst_thumbnailer.moc"
