#include <QSignalSpy>
#include <QTest>

#include "controllers/powerpolicycontroller.h"
#include "managers/displaymanagercpp.h"
#include "services/applifecyclemanager.h"

void DisplayManagerCpp::setScreenState(bool, const QString &) {}
void AppLifecycleManager::setIdleFreezeDebounceMs(int) {}

// wake(reason) is how a call, a message or an alarm turns the screen on.
class TestPowerPolicyWake : public QObject {
    Q_OBJECT

  private slots:
    void wakingFromDozeLeavesDoze() {
        PowerPolicyController policy(nullptr, nullptr);
        QVERIFY(policy.enterDoze(QStringLiteral("power key")));
        QSignalSpy exited(&policy, &PowerPolicyController::dozeExited);
        QSignalSpy waking(&policy, &PowerPolicyController::systemWaking);

        QCOMPARE(policy.wake(QStringLiteral("alarm")), QStringLiteral("alarm"));
        QVERIFY(!policy.dozing());
        QCOMPARE(exited.count(), 1);
        QCOMPARE(waking.last().at(0).toString(), QStringLiteral("alarm"));

        // The power key can put it back to sleep.
        QSignalSpy entered(&policy, &PowerPolicyController::dozeEntered);
        policy.enterDoze(QStringLiteral("power key"));
        QCOMPARE(entered.count(), 1);
    }

    void wakingAnAwakeDeviceDoesNotTouchDoze() {
        PowerPolicyController policy(nullptr, nullptr);
        QSignalSpy            exited(&policy, &PowerPolicyController::dozeExited);
        QSignalSpy            waking(&policy, &PowerPolicyController::systemWaking);
        policy.wake(QStringLiteral("call"));
        QCOMPARE(exited.count(), 0);
        QCOMPARE(waking.count(), 1);
        QCOMPARE(waking.first().at(0).toString(), QStringLiteral("call"));
    }
};

QTEST_GUILESS_MAIN(TestPowerPolicyWake)
#include "test_powerpolicywake.moc"
