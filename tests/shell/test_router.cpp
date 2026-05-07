#include <QTest>
#include <QSignalSpy>
#include "../../shell/src/services/router.h"

class TestRouter : public QObject {
    Q_OBJECT

  private slots:

    // === CONTRACT: Initial state is apps page (index 2) ===

    void initialState() {
        Router r;
        QCOMPARE(r.currentPageIndex(), r.pageApps());
        QCOMPARE(r.previousPageIndex(), r.pageApps());
        QCOMPARE(r.pageHub(), 0);
        QCOMPARE(r.pageFrames(), 1);
        QCOMPARE(r.pageApps(), 2);
    }

    // === CONTRACT: goToHub sets page to 0, emits signals ===

    void goToHub() {
        Router     r;
        QSignalSpy indexSpy(&r, &Router::currentPageIndexChanged);
        QSignalSpy prevSpy(&r, &Router::previousPageIndexChanged);
        QSignalSpy navSpy(&r, &Router::navigateToHub);

        r.goToHub();

        QCOMPARE(r.currentPageIndex(), 0);
        QCOMPARE(r.previousPageIndex(), r.pageApps());
        QCOMPARE(indexSpy.count(), 1);
        QCOMPARE(navSpy.count(), 1);
    }

    // === CONTRACT: goToFrames sets page to 1 ===

    void goToFrames() {
        Router     r;
        QSignalSpy navSpy(&r, &Router::navigateToFrames);

        r.goToFrames();

        QCOMPARE(r.currentPageIndex(), 1);
        QCOMPARE(navSpy.count(), 1);
    }

    // === CONTRACT: goToAppPage adds offset to pageApps ===

    void goToAppPage() {
        Router r;
        r.goToHub();

        QSignalSpy navSpy(&r, &Router::navigateToApps);
        r.goToAppPage(3);

        QCOMPARE(r.currentPageIndex(), r.pageApps() + 3);
        QCOMPARE(navSpy.count(), 1);
        QCOMPARE(navSpy.first().first().toInt(), 3);
    }

    // === CONTRACT: goBack restores previous page ===

    void goBack() {
        Router r;
        r.goToHub();
        QCOMPARE(r.currentPageIndex(), 0);

        r.goBack();

        QCOMPARE(r.currentPageIndex(), r.pageApps());
    }

    // === CONTRACT: goBack swaps current and previous, so double-back toggles ===

    void goBackTwiceToggles() {
        Router r;
        r.goToHub(); // current=0, previous=2
        r.goBack();  // current=2, previous=0
        r.goBack();  // current=0, previous=2

        QCOMPARE(r.currentPageIndex(), r.pageHub());
    }

    // === CONTRACT: navigateLeft increases page index by 1 ===

    void navigateLeftIncrements() {
        Router r;
        int    before = r.currentPageIndex();

        r.navigateLeft();

        QCOMPARE(r.currentPageIndex(), before + 1);
        QCOMPARE(r.previousPageIndex(), before);
    }

    // === CONTRACT: navigateRight decreases page index by 1 ===

    void navigateRightDecrements() {
        Router r;
        r.goToAppPage(2); // index = 4
        int before = r.currentPageIndex();

        r.navigateRight();

        QCOMPARE(r.currentPageIndex(), before - 1);
    }

    // === CONTRACT: navigateRight at 0 is a no-op ===

    void navigateRightAtZeroIsNoop() {
        Router r;
        r.goToHub();
        QCOMPARE(r.currentPageIndex(), 0);

        QSignalSpy spy(&r, &Router::currentPageIndexChanged);
        r.navigateRight();

        QCOMPARE(r.currentPageIndex(), 0);
        QCOMPARE(spy.count(), 0);
    }

    // === CONTRACT: navigateLeft at 10 is a no-op ===

    void navigateLeftAtMaxIsNoop() {
        Router r;
        r.goToAppPage(8); // index = 10

        QSignalSpy spy(&r, &Router::currentPageIndexChanged);
        r.navigateLeft();

        QCOMPARE(r.currentPageIndex(), 10);
        QCOMPARE(spy.count(), 0);
    }

    // === CONTRACT: getCurrentPage returns offset from pageApps ===

    void getCurrentPageOffset() {
        Router r;
        r.goToAppPage(3);
        QCOMPARE(r.getCurrentPage(), 3);

        r.goToHub();
        QCOMPARE(r.getCurrentPage(), 0 - r.pageApps());
    }

    // === CONTRACT: navigateToSetting emits signal ===

    void navigateToSettingEmitsSignal() {
        Router     r;
        QSignalSpy spy(&r, &Router::navigateToSettingPage);

        r.navigateToSetting("wifi");

        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.first().first().toString(), QString("wifi"));
    }

    // === CONTRACT: Same page does not re-emit ===

    void samePageNoEmit() {
        Router r;
        r.goToHub();
        QSignalSpy spy(&r, &Router::currentPageIndexChanged);
        r.goToHub();
        QCOMPARE(spy.count(), 0);
    }
};

QTEST_MAIN(TestRouter)
#include "test_router.moc"
