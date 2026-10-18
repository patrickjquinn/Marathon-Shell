#include <QTest>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>

#include "platformtypes.h"

class TestPlatformTypes : public QObject {
    Q_OBJECT

  private slots:
    void registersRunnerClientsUnderPlatformNames() {
        QQmlEngine engine;
        QObject    permissions;
        QObject    contacts;
        engine.rootContext()->setContextProperty("PermissionManager", &permissions);
        engine.rootContext()->setContextProperty("ContactsManager", &contacts);

        const QStringList registered = registerPlatformTypes(engine.rootContext());
        QVERIFY(registered.contains("Permissions"));
        QVERIFY(registered.contains("Contacts"));
        QVERIFY(!registered.contains("Telephony"));

        QQmlComponent c(&engine);
        c.setData("import QtQml\nimport Marathon.Platform\n"
                  "QtObject { property QtObject p: Permissions; property QtObject c: Contacts }",
                  QUrl());
        QScopedPointer<QObject> o(c.create());
        QVERIFY2(o, qPrintable(c.errorString()));
        QCOMPARE(o->property("p").value<QObject *>(), &permissions);
        QCOMPARE(o->property("c").value<QObject *>(), &contacts);
    }

    void mapsEveryRunnerService() {
        const auto names = platformTypeNames();
        QCOMPARE(names.value("SettingsManagerCpp"), QString("Settings"));
        QCOMPARE(names.value("TelephonyService"), QString("Telephony"));
        QCOMPARE(names.value("NetworkManagerCpp"), QString("Network"));
        QCOMPARE(names.value("AppLifecycleManager"), QString("Lifecycle"));
        QCOMPARE(names.value("HapticService"), QString("Haptics"));
        for (const QString &name : names)
            QVERIFY2(name.at(0).isUpper() && !name.endsWith("Cpp") && !name.endsWith("Manager"),
                     qPrintable(name));
    }
};

QTEST_MAIN(TestPlatformTypes)
#include "test_platformtypes.moc"
