#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include "dataencryption.h"

class TestDataEncryption : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    QString       path(const QString &name) const {
        return m_dir.filePath(name);
    }

    void write(const QString &name, const QByteArray &data) {
        QDir().mkpath(QFileInfo(path(name)).path());
        QFile f(path(name));
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
        f.write(data);
    }

    QString state(const QString &home = "/home/user") const {
        return dataEncryptionState(home, path("mountinfo"), path("sys"), path("state"),
                                   path("marathon_data"));
    }

  private slots:
    void init() {
        QDir(path("sys")).removeRecursively();
        QFile::remove(path("state"));
        write("marathon_data", "");
        // A/B Pi: / is the slot, /var the LUKS data partition, /home bound from it.
        write("mountinfo",
              "22 1 179:4 / / rw,relatime - ext4 /dev/mmcblk0p4 rw\n"
              "30 22 253:0 / /var rw,noatime - ext4 /dev/mapper/marathon_data rw\n"
              "31 22 253:0 /home /home rw,noatime - ext4 /dev/mapper/marathon_data rw\n"
              "32 22 0:30 / /home/user/mnt\\040x rw - tmpfs tmpfs rw\n");
        write("sys/253:0/dm/uuid", "CRYPT-LUKS2-0a1b2c3d-marathon_data\n");
        write("sys/179:4/dev", "179:4\n");
    }

    void openUntilAPinIsSet() {
        QCOMPARE(state(), QStringLiteral("open"));
        write("state", "open\n");
        QCOMPARE(state(), QStringLiteral("open"));
        write("state", "pin\n");
        QCOMPARE(state(), QStringLiteral("pin"));
    }

    void homeOnAPlainPartitionIsOff() {
        write("sys/253:0/dm/uuid", "LVM-abc\n");
        write("state", "pin\n");
        QCOMPARE(state(), QStringLiteral("off"));
        QDir(path("sys/253:0")).removeRecursively();
        QCOMPARE(state(), QStringLiteral("off"));
    }

    void theLongestMountPointWins() {
        write("sys/0:30/dm/uuid", "");
        QCOMPARE(state("/home/user/mnt x/file"), QStringLiteral("off"));
        QCOMPARE(state("/home/user/mntx"), QStringLiteral("open"));
        QCOMPARE(state("/root"), QStringLiteral("off"));
    }

    void noMountInfoIsOff() {
        QFile::remove(path("mountinfo"));
        QCOMPARE(state(), QStringLiteral("off"));
    }

    void noDataPartitionIsNone() {
        QFile::remove(path("marathon_data"));
        QDir(path("sys/253:0")).removeRecursively();
        QCOMPARE(state(), QStringLiteral("none"));
        write("sys/253:0/dm/uuid", "CRYPT-LUKS2-0a1b2c3d-root\n");
        QCOMPARE(state(), QStringLiteral("open"));
    }
};

QTEST_MAIN(TestDataEncryption)
#include "test_dataencryption.moc"
