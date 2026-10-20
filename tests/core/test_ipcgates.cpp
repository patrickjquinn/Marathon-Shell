// Every method a device or personal-data interface of the shell exports
// checks the caller's permission before it acts or answers. Read from the
// source, as a D-Bus round trip per method would need the whole shell.

#include <QFile>
#include <QRegularExpression>
#include <QTest>

namespace {

    QString read(const QString &relative) {
        QFile f(QStringLiteral(MARATHON_SOURCE_DIR "/") + relative);
        if (!f.open(QIODevice::ReadOnly))
            qFatal("cannot read %s", qPrintable(relative));
        return QString::fromUtf8(f.readAll());
    }

    // The slot names a class declares under "public slots:".
    QStringList slotsOf(const QString &header, const QString &cls) {
        static const QRegularExpression nextSection(QStringLiteral("\n  [a-z]+:"));
        static const QRegularExpression declaration(
            QStringLiteral(R"((\w+)\s*\([^;]*\)\s*(const\s*)?;)"));
        const qsizetype start   = header.indexOf(QStringLiteral("class %1 ").arg(cls));
        const qsizetype section = header.indexOf(QStringLiteral("public slots:"), start);
        const qsizetype end     = header.indexOf(nextSection, section + 1);
        if (start < 0 || section < 0 || end < 0)
            return {};
        QStringList names;
        auto        it = declaration.globalMatch(header.mid(section, end - section));
        while (it.hasNext())
            names << it.next().captured(1);
        return names;
    }

    QString bodyOf(const QString &source, const QString &cls, const QString &method) {
        const QRegularExpression def(
            QStringLiteral(R"(\b%1::%2\([^)]*\)[^{;]*\{)").arg(cls, method));
        const QRegularExpressionMatch m =
            def.match(source); // clazy:exclude=use-static-qregularexpression (runtime pattern)
        if (!m.hasMatch())
            return {};
        int       depth = 1;
        qsizetype i     = m.capturedEnd();
        for (; i < source.size() && depth > 0; ++i) {
            if (source.at(i) == QLatin1Char('{'))
                ++depth;
            else if (source.at(i) == QLatin1Char('}'))
                --depth;
        }
        return source.mid(m.capturedEnd(), i - m.capturedEnd());
    }

} // namespace

class TestIpcGates : public QObject {
    Q_OBJECT

  private slots:
    // A refused call for a permission the app declared but was never asked
    // about asks the user rather than failing silently.
    void theGateAsksForUndecidedPermissions() {
        const QString source = read(QStringLiteral("shell/src/ipc/shellservices.cpp"));
        const QString gate   = bodyOf(source, QStringLiteral("IpcPermissionedService"),
                                      QStringLiteral("admit"));
        QVERIFY(gate.contains(QStringLiteral("askIfUndecided(caller, permissions)")));
        QVERIFY(read(QStringLiteral("shell/main.cpp"))
                    .contains(QStringLiteral(
                        "askIfUndecided(desktopId, {QStringLiteral(\"location\")})")));
    }

    void deviceAndPersonalInterfacesCheckPermissions_data() {
        QTest::addColumn<QString>("cls");
        for (const char *cls :
             {"ContactsObject", "TelephonyObject",
              "MediaLibraryObject", "SecurityObject", "BluetoothObject", "DisplayObject",
              "PowerObject", "AudioObject", "NetworkObject", "ModemObject", "SensorObject",
              "LocationObject", "AlarmObject", "UpdatesObject", "DavObject", "AppStoreObject",
              "PermissionsObject"})
            QTest::newRow(cls) << QString::fromLatin1(cls);
    }

    void deviceAndPersonalInterfacesCheckPermissions() {
        QFETCH(QString, cls);
        // Turning the screen on is a power-button press; the lock screen
        // still guards everything behind it.
        const QStringList open = {QStringLiteral("DisplayObject::Wake")};

        const QString     header  = read(QStringLiteral("shell/src/ipc/shellservices.h"));
        const QString     source  = read(QStringLiteral("shell/src/ipc/shellservices.cpp"));
        const QStringList methods = slotsOf(header, cls);
        QVERIFY2(!methods.isEmpty(), qPrintable(cls));
        QVERIFY2(
            header.contains(QStringLiteral("class %1 : public IpcPermissionedService").arg(cls)),
            qPrintable(cls));
        static const QRegularExpression gate(QStringLiteral(
            R"(\brequire\w*\(|authorizePermissionCall\(|hasAnyPermission\(|checkCaller\w*\(|\badmit\()"));
        for (const QString &method : methods) {
            const QString name = cls + QStringLiteral("::") + method;
            if (open.contains(name))
                continue;
            const QString body = bodyOf(source, cls, method);
            QVERIFY2(!body.isEmpty(), qPrintable(name + " has no definition"));
            QVERIFY2(gate.match(body).hasMatch(), qPrintable(name + " checks no permission"));
        }
    }
};

QTEST_GUILESS_MAIN(TestIpcGates)
#include "test_ipcgates.moc"
