#include "managers/soundname.h"

#include <QTest>

class TestSoundName : public QObject {
    Q_OBJECT

  private slots:
    void formats_data() {
        QTest::addColumn<QString>("path");
        QTest::addColumn<QString>("name");
        QTest::newRow("ringtone") << "/usr/share/sounds/ring_classic_phone.wav" << "Classic Phone";
        QTest::newRow("alarm") << "/usr/share/sounds/alarm_early-riser.ogg" << "Early Riser";
        QTest::newRow("url") << "file:///usr/share/sounds/bbpro1.wav" << "Bbpro1";
        QTest::newRow("empty") << "" << "";
    }
    void formats() {
        QFETCH(QString, path);
        QFETCH(QString, name);
        QCOMPARE(formatSoundName(path), name);
    }
};

QTEST_GUILESS_MAIN(TestSoundName)
#include "test_soundname.moc"
