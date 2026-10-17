// Every setting the Settings app writes must reach the shell and be read
// there: a property on the runner's SettingsClient, a GetState/SetProperty
// case in the shell's Settings service, a property on SettingsManager, and a
// named shell consumer. The app's QML stubs must match the real clients.

#include <QDirIterator>
#include <QFile>
#include <QMetaProperty>
#include <QRegularExpression>
#include <QSet>
#include <QTest>

#include "ipc/shellipcclients.h"
#include "managers/settingsmanager.h"

namespace {

    const QString kRoot = QStringLiteral(MARATHON_SOURCE_DIR);

    QString       read(const QString &relative) {
        QFile f(kRoot + QLatin1Char('/') + relative);
        if (!f.open(QIODevice::ReadOnly))
            qFatal("cannot read %s", qPrintable(relative));
        return QString::fromUtf8(f.readAll());
    }

    QSet<QString> matches(const QString &text, const QString &pattern) {
        QSet<QString> out;
        auto          it = QRegularExpression(pattern).globalMatch(text);
        while (it.hasNext())
            out.insert(it.next().captured(1));
        return out;
    }

    // The Settings app's QML and JS, without its tests.
    QString settingsAppQml() {
        QString      all;
        QDirIterator it(kRoot + QStringLiteral("/apps/settings"), {"*.qml", "*.js"}, QDir::Files,
                        QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            if (path.contains(QLatin1String("/tests/")))
                continue;
            QFile f(path);
            if (f.open(QIODevice::ReadOnly))
                all += QString::fromUtf8(f.readAll());
        }
        return all;
    }

    QSet<QString> writtenSettingsKeys() {
        QSet<QString> keys = matches(settingsAppQml(), R"re(\bSettings\.(\w+)\s*=[^=])re");
        // SoundPickerPage writes Settings[key] from its soundType -> key map.
        const QString picker = read("apps/settings/pages/SoundPickerPage.qml");
        const QString keyLine =
            QRegularExpression(R"re(property string key:([^\n]*))re").match(picker).captured(1);
        keys += matches(keyLine, R"re(\w+:\s*"(\w+)")re");
        keys += matches(read("apps/settings/src/KeyboardSettingsStore.cpp"),
                        R"re(writeSettingValue\("(\w+)")re");
        keys += matches(read("apps/settings/src/SettingsController.cpp"),
                        R"re(m_settingsManager->setProperty\("(\w+)")re");
        return keys;
    }

    struct Consumer {
        const char *file;
        const char *token;
    };

    // Where the shell acts on each key. A key with no entry fails the test.
    const QHash<QString, Consumer> kConsumers = {
        {"alarmSound", {"shell/src/managers/alarmmanagercpp.cpp", "alarmSound"}},
        {"appGridColumns", {"shell/qml/components/MarathonAppGrid.qml", "appGridColumns"}},
        {"autoLockTimeout", {"shell/qml/MarathonShell.qml", "SettingsManagerCpp.autoLockTimeout"}},
        {"vibrationEnabled", {"shell/qml/components/VirtualKeyboard.qml", "SettingsManagerCpp.vibrationEnabled"}},
        // The setter applies it through timedated.
        {"automaticTime", {"shell/src/managers/settingsmanager.cpp", "SetNTP"}},
        {"automaticTimeZone",
         {"shell/src/services/automatictimezone.cpp", "m_settings->automaticTimeZone()"}},
        {"deviceName", {"shell/main.cpp", "setAdapterAlias(settingsManager->deviceName())"}},
        {"appNotificationSettings",
         {"shell/src/services/notificationservicecpp.cpp", "isNotificationsEnabledForApp"}},
        {"dndEnabled", {"shell/src/controllers/audiopolicycontroller.cpp", "dndEnabled"}},
        {"enabledQuickSettingsTiles",
         {"shell/qml/components/MarathonQuickSettings.qml", "enabledQuickSettingsTiles"}},
        {"filterMobileFriendlyApps", {"shell/main.cpp", "filterMobileFriendlyApps"}},
        {"hiddenApps", {"shell/qml/models/FilteredAppModel.qml", "hiddenApps"}},
        {"keyboardAutoCapitalize",
         {"shell/qml/keyboard/Core/MarathonKeyboard.qml", "keyboardAutoCapitalize"}},
        {"keyboardAutoCorrection",
         {"shell/qml/keyboard/Core/MarathonKeyboard.qml", "keyboardAutoCorrection"}},
        {"keyboardHapticStrength",
         {"shell/qml/components/VirtualKeyboard.qml", "keyboardHapticStrength"}},
        {"keyboardLanguage", {"shell/src/services/languagemanager.cpp", "keyboardLanguage"}},
        {"keyboardPredictiveText",
         {"shell/qml/keyboard/Core/MarathonKeyboard.qml", "keyboardPredictiveText"}},
        {"notificationSound",
         {"shell/src/controllers/audiopolicycontroller.cpp", "notificationSound"}},
        {"reduceMotion", {"shell/qml/theme/MMotion.qml", "reduceMotion"}},
        {"ringtone", {"shell/src/controllers/audiopolicycontroller.cpp", "ringtone"}},
        {"screenTimeout", {"shell/qml/MarathonShell.qml", "SettingsManagerCpp.screenTimeout"}},
        {"searchNativeApps",
         {"shell/src/services/unifiedsearchservicecpp.cpp", "searchNativeApps"}},
        {"showNotificationBadges",
         {"shell/qml/components/MarathonAppGrid.qml", "showNotificationBadges"}},
        {"showNotificationsOnLockScreen",
         {"shell/qml/components/MarathonLockScreen.qml", "showNotificationsOnLockScreen"}},
        {"timeFormat", {"shell/src/services/systemstatusstore.cpp", "timeFormat"}},
        // The setter applies it through timedated.
        {"timeZone", {"shell/src/managers/settingsmanager.cpp", "SetTimezone"}},
        {"userScaleFactor", {"shell/qml/core/Constants.qml", "userScaleFactor"}},
    };

    const QHash<QString, Consumer> kClientWriteConsumers = {
        {"Display.brightness",
         {"shell/src/managers/displaymanagercpp.cpp",
          "void DisplayManagerCpp::setBrightnessFromUser"}},
        {"Display.autoBrightnessEnabled",
         {"shell/src/managers/displaymanagercpp.cpp", "&DisplayManagerCpp::onAmbientLightChanged"}},
        {"Display.rotationLocked",
         {"shell/src/managers/displaymanagercpp.cpp", "m_rotationManager"}},
        {"Bluetooth.enabled", {"shell/src/managers/bluetoothmanager.cpp", "\"Powered\""}},
    };

    // Written but not yet acted on; each is an open audit finding.
    const QHash<QString, QString> kKnownGaps = {};

    bool hasWritableProperty(const QMetaObject &meta, const QString &name) {
        const int i = meta.indexOfProperty(name.toUtf8().constData());
        return i >= 0 && meta.property(i).isWritable() && meta.property(i).hasNotifySignal();
    }

    // Marathon.Platform names the Settings app uses and the runner clients behind them.
    const QHash<QString, const QMetaObject *> kPlatformClients = {
        {"Settings", &SettingsClient::staticMetaObject},
        {"Display", &DisplayClient::staticMetaObject},
        {"Bluetooth", &BluetoothClient::staticMetaObject},
        {"Network", &NetworkClient::staticMetaObject},
        {"Power", &PowerClient::staticMetaObject},
        {"Audio", &AudioClient::staticMetaObject},
        {"Security", &SecurityClient::staticMetaObject},
        {"Modem", &ModemClient::staticMetaObject},
        {"Permissions", &PermissionClient::staticMetaObject},
    };

} // namespace

class TestSettingsContract : public QObject {
    Q_OBJECT

  private slots:
    void writtenKeys_data() {
        QTest::addColumn<QString>("key");
        const QSet<QString> keys = writtenSettingsKeys();
        QVERIFY(keys.size() > 10);
        for (const QString &key : keys)
            QTest::newRow(qPrintable(key)) << key;
    }

    void writtenKeys() {
        QFETCH(QString, key);
        QVERIFY2(hasWritableProperty(SettingsClient::staticMetaObject, key),
                 "not a writable, notifying property on the runner's SettingsClient");
        QVERIFY2(hasWritableProperty(SettingsManager::staticMetaObject, key),
                 "not a writable, notifying property on the shell's SettingsManager");

        const QString service = read("shell/src/ipc/shellservices.cpp");
        QVERIFY2(service.contains(QStringLiteral("name == \"%1\"").arg(key)),
                 "no SetProperty case in shellservices.cpp");
        QVERIFY2(service.contains(QStringLiteral("{\"%1\", m_settings->").arg(key)),
                 "not in the Settings GetState snapshot");

        if (kKnownGaps.contains(key))
            QSKIP(qPrintable(QStringLiteral("no shell consumer yet (%1)").arg(kKnownGaps[key])));
        QVERIFY2(kConsumers.contains(key), "no shell consumer listed in kConsumers");
        const Consumer c = kConsumers.value(key);
        QVERIFY2(read(QString::fromLatin1(c.file)).contains(QString::fromLatin1(c.token)),
                 qPrintable(QStringLiteral("%1 no longer reads it").arg(c.file)));
    }

    // A keyboard setting the shell never reads is a dead control.
    void keyboardSettingsAreRead() {
        for (const QMetaObject *meta :
             {&SettingsManager::staticMetaObject, &SettingsClient::staticMetaObject}) {
            for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
                const QString name = QString::fromLatin1(meta->property(i).name());
                if (name.startsWith(QLatin1String("keyboard")))
                    QVERIFY2(kConsumers.contains(name),
                             qPrintable(name + QStringLiteral(": no shell consumer")));
            }
        }
    }

    // Writes to other clients: each must be listed with where the shell acts on it.
    void otherClientWrites() {
        const QString qml = settingsAppQml();
        for (const QString &name : {QStringLiteral("Display"), QStringLiteral("Bluetooth")}) {
            const QSet<QString> keys =
                matches(qml, QStringLiteral(R"re(\b%1\.(\w+)\s*=[^=])re").arg(name));
            for (const QString &key : keys) {
                const QString full = name + QLatin1Char('.') + key;
                QVERIFY2(hasWritableProperty(*kPlatformClients.value(name), key), qPrintable(full));
                QVERIFY2(kClientWriteConsumers.contains(full),
                         qPrintable(full + QStringLiteral(": no shell consumer listed")));
                const Consumer c = kClientWriteConsumers.value(full);
                QVERIFY2(read(QString::fromLatin1(c.file)).contains(QString::fromLatin1(c.token)),
                         qPrintable(full));
            }
        }
    }

    void platformMembersExist_data() {
        QTest::addColumn<QString>("name");
        for (auto it = kPlatformClients.cbegin(); it != kPlatformClients.cend(); ++it)
            QTest::newRow(qPrintable(it.key())) << it.key();
    }

    // The tests' hand-written stubs can't catch a page using a member the real client lacks.
    void platformMembersExist() {
        QFETCH(QString, name);
        const QMetaObject  *meta = kPlatformClients.value(name);
        const QSet<QString> used =
            matches(settingsAppQml(), QStringLiteral(R"re(\b%1\.(\w+))re").arg(name));
        QVERIFY(!used.isEmpty());
        for (const QString &member : used) {
            const QByteArray m     = member.toUtf8();
            bool             found = meta->indexOfProperty(m.constData()) >= 0;
            for (int i = 0; !found && i < meta->methodCount(); ++i)
                found = meta->method(i).name() == m;
            QVERIFY2(found, qPrintable(name + QLatin1Char('.') + member));
        }
    }

    // The runner hands Settings the modem under the name platformtypes publishes as Modem.
    void modemReachesTheRunner() {
        QVERIFY(read("tools/marathon-app-runner/platformtypes.cpp")
                    .contains(R"({QStringLiteral("ModemManagerCpp"), QStringLiteral("Modem")})"));
        QVERIFY(read("tools/marathon-app-runner/main.cpp")
                    .contains(R"(setContextProperty("ModemManagerCpp", new ModemClient)"));
        QVERIFY(read("shell/src/ipc/shellipcserver.cpp").contains("/org/marathonos/Shell/Modem"));
    }

    void quickSettingsTileIds() {
        const QSet<QString> settingsIds =
            matches(read("apps/settings/SettingsLogic.js"), R"re(\{ id: "(\w+)", label:)re");
        const QString       qs       = read("shell/qml/components/MarathonQuickSettings.qml");
        // Tiles are listed as { id: ... }; Power is a header button gated by its id.
        const QSet<QString> shellIds = matches(qs, R"re(\{ id: "(\w+)",)re")
            + matches(qs, R"re(enabledQuickSettingsTiles\.indexOf\("(\w+)"\))re");
        QVERIFY(!settingsIds.isEmpty());
        for (const QString &id : settingsIds)
            QVERIFY2(shellIds.contains(id),
                     qPrintable(id + QStringLiteral(" is not a top menu tile")));
    }
};

QTEST_GUILESS_MAIN(TestSettingsContract)
#include "test_settingscontract.moc"
