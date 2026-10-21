// Every method a device or personal-data interface of the shell exports
// checks the caller's permission before it acts or answers. Read from the
// source, as a D-Bus round trip per method would need the whole shell.

#include <QFile>
#include <QTest>

namespace {

    QString read(const QString &relative) {
        QFile f(QStringLiteral(MARATHON_SOURCE_DIR "/") + relative);
        if (!f.open(QIODevice::ReadOnly))
            qFatal("cannot read %s", qPrintable(relative));
        return QString::fromUtf8(f.readAll());
    }

} // namespace

class TestIpcGates : public QObject {
    Q_OBJECT

  private slots:
    // A refused call for a permission the app declared but was never asked
    // about asks the user rather than failing silently.
    void theGateAsksForUndecidedPermissions() {
        QVERIFY(read(QStringLiteral("crates/marathon-shell-native/src/gate.rs"))
                    .contains(QStringLiteral("permissions::ask_if_undecided(&caller, permissions)")));
        QVERIFY(read(QStringLiteral("crates/marathon-shell-native/src/location.rs"))
                    .contains(QStringLiteral("permissions::ask_if_undecided(desktop_id")));
    }
};

QTEST_GUILESS_MAIN(TestIpcGates)
#include "test_ipcgates.moc"
