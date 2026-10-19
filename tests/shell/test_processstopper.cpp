#include <QElapsedTimer>
#include <QFile>
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
        // Let the trap install before the test signals it; a loaded host
        // takes its time.
        p->waitForReadyRead(30000);
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
        // Well within the grace: nothing was killed.
        stopper.stop({quick->processId(), slow->processId()}, 20000);
        QVERIFY(finished.wait(20000));
        QVERIFY(t.elapsed() < 10000);
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
        QVERIFY(finished.wait(20000));
        QVERIFY(t.elapsed() >= 250);
        QCOMPARE(finished.first().first().toInt(), 1);
        QVERIFY(stubborn->waitForFinished(20000));
        QCOMPARE(stubborn->exitStatus(), QProcess::CrashExit);
    }

    void anUnreapedExitCountsAsStopped() {
        QProcess parent;
        parent.start(QStringLiteral("/bin/sh"),
                     {QStringLiteral("-c"), QStringLiteral("sleep 10 & echo $!; exec sleep 10")});
        QVERIFY(parent.waitForReadyRead(30000));
        const qint64   child = parent.readLine().trimmed().toLongLong();
        // Until the shell has become the sleep that never reaps, it would
        // reap the child itself as soon as SIGTERM ends it.
        const auto parentIsSleep = [&parent]() {
            QFile comm(QStringLiteral("/proc/%1/comm").arg(parent.processId()));
            return comm.open(QIODevice::ReadOnly) && comm.readAll().trimmed() == "sleep";
        };
        QTRY_VERIFY_WITH_TIMEOUT(parentIsSleep(), 30000);
        ProcessStopper stopper;
        QSignalSpy     finished(&stopper, &ProcessStopper::finished);
        QElapsedTimer  t;
        t.start();
        stopper.stop({child}, 20000);
        QVERIFY(finished.wait(20000));
        QVERIFY(t.elapsed() < 10000);
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
