#include <QElapsedTimer>
#include <QTemporaryFile>
#include <QtTest>

#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>

#include "drmmasterwait.h"

class TestDrmMasterWait : public QObject {
    Q_OBJECT

  private slots:
    void readsTheConfiguredDevice() {
        QTemporaryFile config;
        QVERIFY(config.open());
        config.write(R"({ "device": "/dev/dri/by-path/platform-x-card", "hwcursor": false })");
        config.flush();
        QCOMPARE(kmsConfigDevice(config.fileName()),
                 QStringLiteral("/dev/dri/by-path/platform-x-card"));
        QVERIFY(kmsConfigDevice(QStringLiteral("/nonexistent.json")).isEmpty());
    }

    void configuredDeviceIsTheOnlyCard() {
        QTemporaryFile config;
        QVERIFY(config.open());
        config.write(R"({ "device": "/dev/dri/card7" })");
        config.flush();
        qputenv("QT_QPA_EGLFS_KMS_CONFIG", config.fileName().toLocal8Bit());
        QCOMPARE(eglfsKmsCards(), QStringList{QStringLiteral("/dev/dri/card7")});
        qunsetenv("QT_QPA_EGLFS_KMS_CONFIG");
    }

    void noWaitWithoutAHolder() {
        QCOMPARE(waitForDrmMaster({}, 5000), 0);
        QCOMPARE(waitForDrmMaster({QStringLiteral("/nonexistent/card0")}, 5000), 0);
    }

    // Needs a KMS card no other process is master of (a host without a
    // running display server, or a VM).
    void waitsWhileAnotherOpenHoldsMaster() {
        const QStringList cards = eglfsKmsCards();
        if (cards.isEmpty())
            QSKIP("no KMS card");
        const int holder = ::open(QFile::encodeName(cards.first()).constData(), O_RDWR | O_CLOEXEC);
        if (holder < 0 || !drmIsMaster(holder)) {
            if (holder >= 0)
                ::close(holder);
            QSKIP("KMS card already has a master");
        }
        QElapsedTimer t;
        t.start();
        QCOMPARE(waitForDrmMaster({cards.first()}, 300), -1);
        QVERIFY(t.elapsed() >= 300);
        ::close(holder);
        QCOMPARE(waitForDrmMaster({cards.first()}, 300), 0);
    }
};

QTEST_GUILESS_MAIN(TestDrmMasterWait)
#include "test_drmmasterwait.moc"
