#include <QTest>

#include "ipc/servicecaller.h"

class TestServiceCaller : public QObject {
    Q_OBJECT

  private:
    QTemporaryDir m_dir;
    QString       m_services, m_proc, m_exec;

    void          process(qint64 pid, const QByteArray &cgroup, const QString &exe) {
        const QString d = QStringLiteral("%1/%2").arg(m_proc).arg(pid);
        QDir().mkpath(d);
        QFile f(d + QStringLiteral("/cgroup"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(cgroup);
        QFile::link(exe, d + QStringLiteral("/exe"));
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        m_services = m_dir.filePath(QStringLiteral("services"));
        m_proc     = m_dir.filePath(QStringLiteral("proc"));
        m_exec     = m_dir.filePath(QStringLiteral("pilotd"));
        QDir().mkpath(m_services);
        QFile exe(m_exec);
        QVERIFY(exe.open(QIODevice::WriteOnly));
        QFile decl(m_services + QStringLiteral("/shoal-pilotd.service.json"));
        QVERIFY(decl.open(QIODevice::WriteOnly));
        decl.write(QStringLiteral(R"({"exec": "%1", "permissions": ["contacts", "calendar"]})")
                       .arg(m_exec)
                       .toUtf8());
    }

    void unitFromCgroup() {
        QCOMPARE(ServiceCaller::unitOf("0::/user.slice/user-1000.slice/user@1000.service/"
                                       "app.slice/shoal-pilotd.service\n"),
                 QStringLiteral("shoal-pilotd.service"));
        QCOMPARE(ServiceCaller::unitOf("0::/user.slice/user-1000.slice/session-2.scope\n"),
                 QString());
        QCOMPARE(ServiceCaller::unitOf("0::/a/../x.service/\n"), QString());
        QCOMPARE(ServiceCaller::unitOf(""), QString());
    }

    void declaredServiceInItsUnit() {
        process(10, "0::/user.slice/app.slice/shoal-pilotd.service\n", m_exec);
        const QString id = ServiceCaller::resolve(10, m_services, m_proc);
        QCOMPARE(id, QStringLiteral("service:shoal-pilotd.service"));
        QVERIFY(ServiceCaller::allowed(id, {QStringLiteral("calendar")}, m_services));
        QVERIFY(!ServiceCaller::allowed(id, {QStringLiteral("system")}, m_services));
        QVERIFY(!ServiceCaller::allowed(QStringLiteral("shoal-pilotd.service"),
                                        {QStringLiteral("calendar")}, m_services));
    }

    void otherProgramInTheUnitIsRefused() {
        process(11, "0::/user.slice/app.slice/shoal-pilotd.service\n", QStringLiteral("/bin/sh"));
        QCOMPARE(ServiceCaller::resolve(11, m_services, m_proc), QString());
    }

    void declaredProgramOutsideItsUnitIsRefused() {
        process(12, "0::/user.slice/user-1000.slice/session-2.scope\n", m_exec);
        QCOMPARE(ServiceCaller::resolve(12, m_services, m_proc), QString());
        process(13, "0::/user.slice/app.slice/other.service\n", m_exec);
        QCOMPARE(ServiceCaller::resolve(13, m_services, m_proc), QString());
        QCOMPARE(ServiceCaller::resolve(14, m_services, m_proc), QString());
    }
};

QTEST_GUILESS_MAIN(TestServiceCaller)
#include "test_servicecaller.moc"
