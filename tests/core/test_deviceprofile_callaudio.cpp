#include "managers/deviceprofile.h"

#include <QTest>

class TestDeviceProfileCallAudio : public QObject {
    Q_OBJECT

  private slots:
    // The L5 keeps its tuned UCM profile switch; other devices route calls
    // through callaudiod.
    void envSelectsCallAudioRouting() {
        qputenv("MARATHON_CALL_AUDIO", "ucm-profiles");
        QCOMPARE(DeviceProfile::instance().callAudio(), QStringLiteral("ucm-profiles"));
    }
};

QTEST_GUILESS_MAIN(TestDeviceProfileCallAudio)
#include "test_deviceprofile_callaudio.moc"
