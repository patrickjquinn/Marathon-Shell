#include <QElapsedTimer>
#include <QProcess>
#include <QSignalSpy>
#include <QTest>

#include <csignal>

#include "processstopper.h"

class TestProcessStopper : public QObject {
    Q_OBJECT

    static QProcess *startShell(const QString &script, QObject *parent) {
        auto *p = new QProcess(parent);
        p->start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), script});
        p->waitForStarted();
        // Let the trap install before the test signals it.
        p->waitForReadyRead(2000);
        return p;
    }

  private slots:
    void finishesOnceAllExitOnSigterm() {
        QObject   owner;
        QProcess *quick = startShell(
            QStringLiteral("trap 'exit 0' TERM; echo up; while :; do sleep 0.05; done"), &owner);
        QProcess *slow = startShell(
            QStringLiteral("trap 'sleep 0.3; exit 0' TERM; echo up; while :; do sleep 0.05; done"),
            &owner);
        ProcessStopper stopper;
        QSignalSpy     finished(&stopper, &ProcessStopper::finished);
        QElapsedTimer  t;
        t.start();
        stopper.stop({quick->processId(), slow->processId()}, 3000);
        QVERIFY(finished.wait(3000));
        QVERIFY(t.elapsed() < 2000);
        QCOMPARE(finished.first().first().toInt(), 0);
        QCOMPARE(quick->exitStatus(), QProcess::NormalExit);
        QCOMPARE(slow->exitStatus(), QProcess::NormalExit);
    }

    void killsWhatIgnoresSigtermAfterGrace() {
        QObject   owner;
        QProcess *stubborn = startShell(
            QStringLiteral("trap '' TERM; echo up; while :; do sleep 0.05; done"), &owner);
        ProcessStopper stopper;
        QSignalSpy     finished(&stopper, &ProcessStopper::finished);
        QElapsedTimer  t;
        t.start();
        stopper.stop({stubborn->processId()}, 300);
        QVERIFY(finished.wait(2000));
        QVERIFY(t.elapsed() >= 250);
        QCOMPARE(finished.first().first().toInt(), 1);
        QVERIFY(stubborn->waitForFinished(2000));
        QCOMPARE(stubborn->exitStatus(), QProcess::CrashExit);
    }

    void anUnreapedExitCountsAsStopped() {
        QProcess parent;
        parent.start(QStringLiteral("/bin/sh"),
                     {QStringLiteral("-c"), QStringLiteral("sleep 10 & echo $!; exec sleep 10")});
        QVERIFY(parent.waitForReadyRead(2000));
        const qint64   child = parent.readLine().trimmed().toLongLong();
        ProcessStopper stopper;
        QSignalSpy     finished(&stopper, &ProcessStopper::finished);
        QElapsedTimer  t;
        t.start();
        stopper.stop({child}, 3000);
        QVERIFY(finished.wait(3000));
        QVERIFY(t.elapsed() < 2000);
        QCOMPARE(finished.first().first().toInt(), 0);
        QVERIFY(::kill(static_cast<pid_t>(child), 0) == 0);
        parent.kill();
        parent.waitForFinished();
    }

    void finishesAtOnceWithNothingToStop() {
        ProcessStopper stopper;
        QSignalSpy     finished(&stopper, &ProcessStopper::finished);
        stopper.stop({-1, 0}, 3000);
        QCOMPARE(finished.count(), 1);
        QCOMPARE(finished.first().first().toInt(), 0);
    }
};

QTEST_GUILESS_MAIN(TestProcessStopper)
#include "test_processstopper.moc"
