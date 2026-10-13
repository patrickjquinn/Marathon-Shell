#include "updateservice.h"

#include <QTest>

class TestUpdateVersion : public QObject {
    Q_OBJECT

  private slots:
    void packageReleasesCompareNumerically() {
        QVERIFY(UpdateService::compareVersion("1.0.0-r1000", "1.0.0-r409") > 0);
        QVERIFY(UpdateService::compareVersion("1.0.0-r409", "1.0.0-r410") < 0);
    }

    void tagPrefixIsIgnored() {
        QCOMPARE(UpdateService::compareVersion("v1.2.0", "1.2.0"), 0);
        QVERIFY(UpdateService::compareVersion("v1.2.0", "1.0.0-r409") > 0);
    }
};

QTEST_GUILESS_MAIN(TestUpdateVersion)
#include "test_updateversion.moc"
