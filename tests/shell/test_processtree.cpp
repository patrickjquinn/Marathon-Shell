#include <QCoreApplication>
#include <QProcess>
#include <QtTest>

#include <csignal>

#include "processtree.h"

class TestProcessTree : public QObject {
    Q_OBJECT

  private slots:
    void childAndGrandchildDescendFromUs() {
        const qint64 self = QCoreApplication::applicationPid();
        QProcess     sh;
        sh.start(QStringLiteral("/bin/sh"),
                 {QStringLiteral("-c"), QStringLiteral("sleep 5 & echo $!; wait")});
        QVERIFY(sh.waitForReadyRead(5000));
        const qint64 grandchild = sh.readLine().trimmed().toLongLong();
        QVERIFY(isDescendantPid(sh.processId(), self));
        QVERIFY(isDescendantPid(grandchild, self));
        QVERIFY(isDescendantPid(grandchild, sh.processId()));
        QVERIFY(!isDescendantPid(self, sh.processId()));
        sh.kill();
        sh.waitForFinished();
        ::kill(static_cast<pid_t>(grandchild), SIGKILL);
    }
};

QTEST_GUILESS_MAIN(TestProcessTree)
#include "test_processtree.moc"
