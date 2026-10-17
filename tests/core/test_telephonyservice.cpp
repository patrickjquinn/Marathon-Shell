#include <QTest>
#include <QSignalSpy>
#include "telephonyservice.h"

class TestTelephonyService : public QObject {
    Q_OBJECT

    static QString endedType(const QSignalSpy &spy) {
        return spy.isEmpty() ? QString() : spy.first().at(1).toString();
    }

  private slots:
    void initTestCase() {
        qputenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent");
    }

    void declinedCallIsRejected() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1234567890");
        phone.hangup();
        QCOMPARE(ended.count(), 1);
        QCOMPARE(ended.first().at(0).toString(), QString("+1234567890"));
        QCOMPARE(endedType(ended), QString("rejected"));
        QCOMPARE(ended.first().at(3).toInt(), 0);
    }

    void callEndedByTheCallerIsMissed() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1555111222");
        phone.simulateCallStateChange("terminated");
        QCOMPARE(ended.count(), 1);
        QCOMPARE(endedType(ended), QString("missed"));
    }

    void callThatStopsRingingIsMissed() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1555123456");
        phone.simulateCallStateChange("idle");
        QCOMPARE(endedType(ended), QString("missed"));
    }

    void answeredCallIsIncomingHoweverShort() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1234567890");
        phone.answer();
        phone.hangup();
        QCOMPARE(ended.count(), 1);
        QCOMPARE(endedType(ended), QString("incoming"));
    }

    void answeredCallEndedByTheCallerIsIncoming() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1234567890");
        phone.answer();
        phone.simulateCallStateChange("terminated");
        QCOMPARE(endedType(ended), QString("incoming"));
    }

    void outgoingCallIsOutgoing() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateCallStateChange("dialing");
        phone.simulateCallStateChange("active");
        phone.simulateCallStateChange("idle");
        QCOMPARE(endedType(ended), QString("outgoing"));
    }

    void aCallEndsOnce() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1234567890");
        phone.hangup();
        phone.simulateCallStateChange("terminated");
        QCOMPARE(ended.count(), 1);
    }

    void eachCallIsClassifiedOnItsOwn() {
        TelephonyService phone;
        QSignalSpy       ended(&phone, &TelephonyService::callEnded);
        phone.simulateIncomingCall("+1234567890");
        phone.hangup();
        phone.simulateIncomingCall("+1555111222");
        phone.simulateCallStateChange("terminated");
        QCOMPARE(ended.count(), 2);
        QCOMPARE(ended.at(1).at(0).toString(), QString("+1555111222"));
        QCOMPARE(ended.at(1).at(1).toString(), QString("missed"));
    }
};

QTEST_MAIN(TestTelephonyService)
#include "test_telephonyservice.moc"
