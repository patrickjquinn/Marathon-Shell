#include <QTest>

#include "services/inputboost.h"

class TestInputBoost : public QObject {
    Q_OBJECT

  private slots:
    // The floor to come back to: the one in place, unless a shell that
    // ended mid-boost left the boosted floor behind.
    void restingFloor_data() {
        QTest::addColumn<QByteArray>("current");
        QTest::addColumn<QByteArray>("boosted");
        QTest::addColumn<QByteArray>("hardwareMin");
        QTest::addColumn<QByteArray>("resting");
        QTest::newRow("at rest") << QByteArray("1500000") << QByteArray("2400000") << QByteArray("1500000")
                                 << QByteArray("1500000");
        QTest::newRow("tuned floor kept") << QByteArray("1800000") << QByteArray("2400000")
                                          << QByteArray("1500000") << QByteArray("1800000");
        QTest::newRow("left boosted") << QByteArray("2400000") << QByteArray("2400000") << QByteArray("1500000")
                                      << QByteArray("1500000");
    }

    void restingFloor() {
        QFETCH(QByteArray, current);
        QFETCH(QByteArray, boosted);
        QFETCH(QByteArray, hardwareMin);
        QFETCH(QByteArray, resting);
        QCOMPARE(InputBoost::restingFloor(current, boosted, hardwareMin), resting);
    }
};

QTEST_GUILESS_MAIN(TestInputBoost)
#include "test_inputboost.moc"
