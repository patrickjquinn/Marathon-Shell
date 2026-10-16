#include <QSignalSpy>
#include <QTest>

#include "sinkvolume.h"

class FakeSinkBackend : public SinkBackend {
    Q_OBJECT
  public:
    QList<QPair<QString, double>> volumeWrites;
    QList<QPair<QString, bool>>   muteWrites;

    void setSinkVolume(const QString &sink, double volume) override {
        volumeWrites.append({sink, volume});
    }
    void setSinkMuted(const QString &sink, bool muted) override {
        muteWrites.append({sink, muted});
    }

    void finishWrites() {
        for (qsizetype i = 0; i < volumeWrites.size(); ++i)
            emit volumeWritten();
        for (qsizetype i = 0; i < muteWrites.size(); ++i)
            emit muteWritten();
    }
};

class TestSinkVolume : public QObject {
    Q_OBJECT

  private slots:
    // A Bluetooth headset becomes the default after the shell started.
    void followsTheNewDefaultSink() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        emit b.defaultSinkChanged("auto_null");
        emit b.sinkChanged("auto_null", 0.0, false);
        QCOMPARE(v.volume(), 0.0);

        QSignalSpy spy(&v, &SinkVolume::volumeChanged);
        emit b.defaultSinkChanged("bluez_output.AA_BB.1");
        emit b.sinkChanged("bluez_output.AA_BB.1", 0.7, false);
        QCOMPARE(v.sink(), QString("bluez_output.AA_BB.1"));
        QCOMPARE(v.volume(), 0.7);
        QCOMPARE(spy.count(), 1);
    }

    void ignoresOtherSinks() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        emit b.defaultSinkChanged("bluez");
        emit b.sinkChanged("bluez", 0.5, false);
        emit b.sinkChanged("auto_null", 0.1, true);
        QCOMPARE(v.volume(), 0.5);
        QVERIFY(!v.muted());
    }

    void followsMuteOfTheDefaultSink() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        QSignalSpy      spy(&v, &SinkVolume::mutedChanged);
        emit b.defaultSinkChanged("bluez");
        emit b.sinkChanged("bluez", 0.5, true);
        QVERIFY(v.muted());
        QCOMPARE(spy.count(), 1);
    }

    void writesGoToTheCurrentDefault() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        emit b.defaultSinkChanged("auto_null");
        emit b.defaultSinkChanged("bluez");
        v.setVolume(0.4);
        v.setMuted(true);
        QCOMPARE(b.volumeWrites, (QList<QPair<QString, double>>{{"bluez", 0.4}}));
        QCOMPARE(b.muteWrites, (QList<QPair<QString, bool>>{{"bluez", true}}));
    }

    void clampsVolume() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        emit b.defaultSinkChanged("s");
        v.setVolume(1.5);
        QCOMPARE(b.volumeWrites.last().second, 1.0);
        b.finishWrites();
        emit b.sinkChanged("s", 1.3, false);
        QCOMPARE(v.volume(), 1.0);
    }

    // At boot the profile's mute arrives before the server has a default.
    void writesBeforeASinkAreAppliedToTheFirst() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        v.setMuted(true);
        v.setVolume(0.9);
        QVERIFY(b.muteWrites.isEmpty());
        QVERIFY(b.volumeWrites.isEmpty());
        emit b.defaultSinkChanged("s");
        QCOMPARE(b.muteWrites, (QList<QPair<QString, bool>>{{"s", true}}));
        QCOMPARE(b.volumeWrites, (QList<QPair<QString, double>>{{"s", 0.9}}));

        // Its state before the writes landed does not undo them.
        emit b.sinkChanged("s", 0.3, false);
        QVERIFY(v.muted());
        QCOMPARE(v.volume(), 0.9);

        b.finishWrites();
        emit b.sinkChanged("s", 0.9, true);
        emit b.defaultSinkChanged("t");
        QCOMPARE(b.volumeWrites.size(), 1);
        QCOMPARE(b.muteWrites.size(), 1);
    }

    // A slider drag: reports of earlier values do not pull the slider back.
    void staleReportsDuringADragAreIgnored() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        emit b.defaultSinkChanged("s");
        emit b.sinkChanged("s", 0.1, false);
        v.setVolume(0.2);
        v.setVolume(0.3);
        emit b.volumeWritten();
        emit b.sinkChanged("s", 0.2, false);
        QCOMPARE(v.volume(), 0.3);
        emit b.volumeWritten();
        emit b.sinkChanged("s", 0.3, false);
        QCOMPARE(v.volume(), 0.3);

        emit b.sinkChanged("s", 0.6, false);
        QCOMPARE(v.volume(), 0.6);
    }

    // Mute in flight does not hold back a volume change, and vice versa.
    void fieldsAreIndependent() {
        FakeSinkBackend b;
        SinkVolume      v(&b);
        emit b.defaultSinkChanged("s");
        emit b.sinkChanged("s", 0.5, false);
        v.setMuted(true);
        emit b.sinkChanged("s", 0.8, false);
        QCOMPARE(v.volume(), 0.8);
        QVERIFY(v.muted());
    }
};

QTEST_GUILESS_MAIN(TestSinkVolume)
#include "test_sinkvolume.moc"
