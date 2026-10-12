#include <QSignalSpy>
#include <QtTest>

#include "ngfservice.h"

class TestNgfService : public QObject {
    Q_OBJECT

    QList<QList<int>> played;
    int               stops = 0;

    NgfService *make() {
        played.clear();
        stops = 0;
        return new NgfService([this](const QList<int> &p) { played << p; }, [this]() { ++stops; },
                              this);
    }

  private slots:
    void playReportsPlayingThenCompleted() {
        NgfService *ngf = make();
        QSignalSpy  status(ngf, &NgfService::Status);
        const quint32 id = ngf->Play(QStringLiteral("pulldown_highlight"), {});
        QVERIFY(id > 0);
        QCOMPARE(played.size(), 1);
        QCOMPARE(status.size(), 1);
        QCOMPARE(status.at(0).at(0).toUInt(), id);
        QCOMPARE(status.at(0).at(1).toUInt(), quint32(NgfService::Playing));
        QTRY_COMPARE(status.size(), 2);
        QCOMPARE(status.at(1).at(1).toUInt(), quint32(NgfService::Completed));
    }

    void unknownEventFails() {
        NgfService *ngf = make();
        QSignalSpy  status(ngf, &NgfService::Status);
        const quint32 id = ngf->Play(QStringLiteral("no_such_event"), {});
        QVERIFY(played.isEmpty());
        QTRY_COMPARE(status.size(), 1);
        QCOMPARE(status.at(0).at(0).toUInt(), id);
        QCOMPARE(status.at(0).at(1).toUInt(), quint32(NgfService::Failed));
    }

    void repeatingEventLoopsUntilStopped() {
        NgfService *ngf = make();
        QSignalSpy  status(ngf, &NgfService::Status);
        const quint32 id = ngf->Play(QStringLiteral("alarm"), {});
        QTRY_VERIFY_WITH_TIMEOUT(played.size() >= 2, 3000);
        ngf->Stop(id);
        QCOMPARE(stops, 1);
        QCOMPARE(status.last().at(1).toUInt(), quint32(NgfService::Completed));
        const int count = played.size();
        QTest::qWait(1200);
        QCOMPARE(played.size(), count);
    }

    void stopUnknownIdIsHarmless() {
        NgfService *ngf = make();
        ngf->Stop(12345);
        QCOMPARE(stops, 0);
    }
};

QTEST_GUILESS_MAIN(TestNgfService)
#include "test_ngfservice.moc"
