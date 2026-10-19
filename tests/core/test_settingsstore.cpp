#include <QDBusArgument>
#include <QFile>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>

#include "managers/settingsmanager.h"

// SettingsManager::get/set back app keys such as calendar/events.
class TestSettingsStore : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

  private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
    }

    // Devices that stored a QDBusArgument before Set demarshalled it.
    void unreadableValueReadsAsDefault() {
        {
            QSettings s("marathon-os", "Marathon Shell");
            s.setValue("calendar/events", QVariant::fromValue(QDBusArgument()));
            s.sync();
        }
        SettingsManager m;
        const QVariant v = m.get("calendar/events", QVariantList());
        QCOMPARE(v.typeId(), QMetaType::QVariantList);
        QVERIFY(v.toList().isEmpty());
        QVERIFY(!QSettings("marathon-os", "Marathon Shell").contains("calendar/events"));
    }

    void unstorableValueIsNotWritten() {
        SettingsManager m;
        m.set("calendar/events", QVariantList{QVariantMap{{"title", "Lunch"}}});
        m.set("calendar/events", QVariant::fromValue(QDBusArgument()));
        m.set("calendar/events", QVariantList{QVariant::fromValue(QDBusArgument())});
        const QVariantList events = m.get("calendar/events").toList();
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().toMap().value("title").toString(), QString("Lunch"));
    }

    void uninstalledAppsKeysGo() {
        SettingsManager m;
        m.set("com.gone/token", "x");
        m.set("com.gone/sub/key", 1);
        m.set("com.kept/token", "y");
        m.removeAppKeys("com.gone");
        m.removeAppKeys("");
        QVERIFY(!m.get("com.gone/token").isValid());
        QVERIFY(!m.get("com.gone/sub/key").isValid());
        QCOMPARE(m.get("com.kept/token").toString(), QString("y"));
    }

    // A drag sets the volume per step; the file catches up once it settles.
    void settingsReachTheFileAfterABurst() {
        SettingsManager m;
        for (int v = 1; v <= 40; ++v)
            m.setSystemVolume(v / 100.0);
        const QString path   = m_dir.filePath("marathon-os/Marathon Shell.conf");
        const auto    onDisk = [&path]() {
            QFile file(path);
            return file.open(QIODevice::ReadOnly) && file.readAll().contains("systemVolume=0.4");
        };
        QVERIFY(!onDisk());
        QTRY_VERIFY(onDisk());
    }
};

QTEST_MAIN(TestSettingsStore)
#include "test_settingsstore.moc"
