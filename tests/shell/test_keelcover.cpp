#include <QtTest>

#include "keelcover.h"

class TestKeelCover : public QObject {
    Q_OBJECT

  private slots:
    void markerTitlesAreCovers() {
        QVERIFY(KeelCover::isCoverTitle(QStringLiteral("keel:cover")));
        QVERIFY(KeelCover::isCoverTitle(QStringLiteral("keel:cover:Weather")));
    }
    void otherTitlesAreNot() {
        QVERIFY(!KeelCover::isCoverTitle(QStringLiteral("keel:covered")));
        QVERIFY(!KeelCover::isCoverTitle(QStringLiteral("Keel:cover")));
        QVERIFY(!KeelCover::isCoverTitle(QStringLiteral("Notes")));
        QVERIFY(!KeelCover::isCoverTitle(QString()));
    }
};

QTEST_GUILESS_MAIN(TestKeelCover)
#include "test_keelcover.moc"
