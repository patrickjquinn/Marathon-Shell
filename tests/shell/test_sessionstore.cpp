#include <QTest>

#include "sessionstore.h"

// Unlocking skips the PIN only within lockDelay seconds of the device
// locking from the unlocked state.
class TestSessionStore : public QObject {
    Q_OBJECT

    qint64 m_now = 1000000;

    void   useFakeClock(SessionStore &s) {
        s.setClock([this] { return m_now; });
    }
    void lockFromUnlocked(SessionStore &s) {
        s.setIsLocked(false);
        s.setIsLocked(true);
    }

  private slots:
    void init() {
        m_now = 1000000;
    }

    void immediatelyNeedsThePin() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(0);
        lockFromUnlocked(s);
        QVERIFY(!s.checkSession());
    }

    void withinGraceSkipsThePin() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(30);
        lockFromUnlocked(s);
        m_now += 29000;
        QVERIFY(s.checkSession());
    }

    void pastGraceNeedsThePin() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(30);
        lockFromUnlocked(s);
        m_now += 30000;
        QVERIFY(!s.checkSession());
    }

    void freshStoreNeedsThePin() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(300);
        QVERIFY(s.isLocked());
        QVERIFY(!s.checkSession());
    }

    void resetNeedsThePin() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(300);
        lockFromUnlocked(s);
        QVERIFY(s.checkSession());
        s.reset();
        QVERIFY(!s.checkSession());
        s.setIsLocked(false);
        s.reset();
        QVERIFY(s.isLocked());
        QVERIFY(!s.checkSession());
    }

    void relockingWhileLockedDoesNotExtendGrace() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(30);
        lockFromUnlocked(s);
        m_now += 20000;
        s.setIsLocked(true);
        s.lock();
        m_now += 15000;
        QVERIFY(!s.checkSession());
    }

    void unlockingEndsGrace() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(30);
        lockFromUnlocked(s);
        s.unlock();
        QTRY_VERIFY(!s.isLocked());
        QVERIFY(!s.checkSession());
    }

    void animatedLockStartsGrace() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(5);
        s.setIsLocked(false);
        s.lock();
        QTRY_VERIFY(s.isLocked());
        m_now += 4000;
        QVERIFY(s.checkSession());
        m_now += 1000;
        QVERIFY(!s.checkSession());
    }

    void negativeDelayIsImmediate() {
        SessionStore s;
        useFakeClock(s);
        s.setLockDelay(-5);
        QCOMPARE(s.lockDelay(), 0);
        lockFromUnlocked(s);
        QVERIFY(!s.checkSession());
    }
};

QTEST_GUILESS_MAIN(TestSessionStore)
#include "test_sessionstore.moc"
