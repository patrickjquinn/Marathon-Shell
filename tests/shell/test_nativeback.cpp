#include <QTest>

#include "nativeback.h"

using namespace NativeBack;

class TestNativeBack : public QObject {
    Q_OBJECT

  private slots:
    void toolkitFromMaps_data() {
        QTest::addColumn<QByteArray>("maps");
        QTest::addColumn<int>("toolkit");
        const QByteArray lib = "7f3c2a000000-7f3c2a1f0000 r-xp 00000000 00:2a 123 ";
        QTest::newRow("libadwaita") << lib + "/usr/lib/aarch64-linux-gnu/libgtk-4.so.1\n" + lib +
                "/usr/lib/aarch64-linux-gnu/libadwaita-1.so.0\n"
                                    << int(Adwaita);
        QTest::newRow("gtk4") << lib + "/usr/lib64/libgtk-4.so.1.1600.0\n" << int(Gtk4);
        QTest::newRow("gtk3") << lib + "/usr/lib/libgtk-3.so.0.2400.41\n" << int(Gtk3);
        QTest::newRow("kirigami") << lib + "/usr/lib/libQt6Core.so.6\n" + lib +
                "/usr/lib/libKF6Kirigami.so.6\n"
                                  << int(QtApp);
        // Qt's gtk3 platform theme maps libgtk-3 into a Qt app.
        QTest::newRow("qt with gtk theme")
            << lib + "/usr/lib/libgtk-3.so.0\n" + lib + "/usr/lib/libQt5Core.so.5\n"
            << int(QtApp);
        QTest::newRow("sdl") << lib + "/usr/lib/libSDL2-2.0.so.0\n" << int(Unknown);
        QTest::newRow("unreadable") << QByteArray() << int(Unknown);
    }

    void toolkitFromMaps() {
        QFETCH(QByteArray, maps);
        QFETCH(int, toolkit);
        QCOMPARE(int(NativeBack::toolkitFromMaps(maps)), toolkit);
    }

    // Escape pops an AdwNavigationView page and closes an AdwDialog; the Back
    // key is what libhandy, Kirigami and the browsers navigate with.
    void backKey() {
        QCOMPARE(NativeBack::backKey(Adwaita, false), int(Qt::Key_Escape));
        QCOMPARE(NativeBack::backKey(Gtk4, false), int(Qt::Key_Escape));
        QCOMPARE(NativeBack::backKey(Gtk3, false), int(Qt::Key_Back));
        QCOMPARE(NativeBack::backKey(QtApp, false), int(Qt::Key_Back));
        QCOMPARE(NativeBack::backKey(Unknown, false), int(Qt::Key_Back));
        QCOMPARE(NativeBack::backKey(QtApp, true), int(Qt::Key_Escape));
    }

    void pageChangeIsVisible() {
        const QSize window(540, 1140);
        QVERIFY(visibleChange(QRegion(0, 0, 540, 1140), window));
        // An AdwDialog sheet closing, or a search bar and the list under it.
        QVERIFY(visibleChange(QRegion(0, 600, 540, 540), window));
        QVERIFY(visibleChange(QRegion(0, 0, 540, 60) + QRegion(0, 200, 540, 100), window));
    }

    void smallRepaintsAreNot() {
        const QSize window(540, 1140);
        QVERIFY(!visibleChange(QRegion(), window));
        QVERIFY(!visibleChange(QRegion(20, 400, 2, 30), window));   // a text cursor
        QVERIFY(!visibleChange(QRegion(240, 500, 64, 64), window)); // a spinner
        QVERIFY(!visibleChange(QRegion(0, 1080, 540, 60), window)); // a level meter strip
        QVERIFY(!visibleChange(QRegion(0, 0, 540, 1140), QSize())); // unmapped window
    }
};

QTEST_GUILESS_MAIN(TestNativeBack)
#include "test_nativeback.moc"
