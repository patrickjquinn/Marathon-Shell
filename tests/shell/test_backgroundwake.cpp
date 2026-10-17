#include <QTest>
#include <QTemporaryDir>
#include <QFile>

#include "powermanagercpp.h"

// marathon-background arm-wake writes the time it armed to a marker file;
// a resume at that time is the device waking for background work.
class TestBackgroundWake : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    QString       marker(const QByteArray &contents) {
        const QString path = m_dir.filePath(QStringLiteral("wake"));
        QFile         file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
            qFatal("cannot write %s", qPrintable(path));
        file.write(contents);
        return path;
    }

  private slots:
    void aResumeAtTheArmedTimeIsABackgroundWake() {
        const QString path = marker("1792236376\n");
        QVERIFY(PowerManagerCpp::isBackgroundWake(path, 1792236376));
        QVERIFY(PowerManagerCpp::isBackgroundWake(path, 1792236376 - 10));
        QVERIFY(PowerManagerCpp::isBackgroundWake(path, 1792236376 + 60));
    }

    void aResumeAtAnyOtherTimeIsThePersons() {
        const QString path = marker("1792236376\n");
        QVERIFY(!PowerManagerCpp::isBackgroundWake(path, 1792236376 - 11));
        QVERIFY(!PowerManagerCpp::isBackgroundWake(path, 1792236376 + 61));
    }

    void noMarkerOrAnUnreadableOneIsNoBackgroundWake() {
        QVERIFY(!PowerManagerCpp::isBackgroundWake(m_dir.filePath(QStringLiteral("none")), 0));
        QVERIFY(!PowerManagerCpp::isBackgroundWake(marker("soon"), 0));
        QVERIFY(!PowerManagerCpp::isBackgroundWake(marker(""), 0));
    }
};

QTEST_GUILESS_MAIN(TestBackgroundWake)
#include "test_backgroundwake.moc"
