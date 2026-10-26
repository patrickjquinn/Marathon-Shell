#include <QtTest>

#include "services/touchdevices.h"

class TestTouchDevices : public QObject {
    Q_OBJECT

  private:
    int                opened = 0;
    int                closed = 0;

    TouchDevices::Open open() {
        return [this](const QString &) {
            ++opened;
            auto handler = std::make_unique<QObject>();
            connect(handler.get(), &QObject::destroyed, this, [this] { ++closed; });
            return handler;
        };
    }

  private slots:
    void init() {
        opened = 0;
        closed = 0;
    }

    void sameNodeTwiceOpensOnce() {
        TouchDevices devices(open());
        QVERIFY(devices.add(QStringLiteral("/dev/input/event9")));
        QVERIFY(!devices.add(QStringLiteral("/dev/input/event9")));
        QCOMPARE(devices.count(), 1);
        QCOMPARE(opened, 1);
    }

    void removedNodeOpensAgainOnce() {
        TouchDevices devices(open());
        devices.add(QStringLiteral("/dev/input/event9"));
        QVERIFY(devices.remove(QStringLiteral("/dev/input/event9")));
        QCOMPARE(devices.count(), 0);
        QCOMPARE(closed, 1);
        devices.add(QStringLiteral("/dev/input/event9"));
        devices.add(QStringLiteral("/dev/input/event9"));
        QCOMPARE(devices.count(), 1);
        QCOMPARE(opened, 2);
    }

    void twoNodesOpenTwo() {
        TouchDevices devices(open());
        devices.add(QStringLiteral("/dev/input/event9"));
        devices.add(QStringLiteral("/dev/input/event12"));
        QCOMPARE(devices.count(), 2);
        QCOMPARE(devices.handlers().size(), 2);
        QVERIFY(!devices.remove(QStringLiteral("/dev/input/event3")));
        QCOMPARE(devices.count(), 2);
    }

    void failedOpenIsNotKept() {
        TouchDevices devices([](const QString &) { return std::unique_ptr<QObject>(); });
        QVERIFY(!devices.add(QStringLiteral("/dev/input/event9")));
        QCOMPARE(devices.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestTouchDevices)
#include "test_touchdevices.moc"
