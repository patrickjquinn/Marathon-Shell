#include <QDBusArgument>
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
};

QTEST_MAIN(TestSettingsStore)
#include "test_settingsstore.moc"
