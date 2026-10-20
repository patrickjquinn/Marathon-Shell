// Every setting the Settings app writes must reach the shell and be read
// there: a property on the runner's Settings, a GetState/SetProperty
// case in the shell's Settings service, a property on SettingsManager, and a
// named shell consumer. The app's QML stubs must match the real clients.

#include <QDirIterator>
#include <QFile>
#include <QMetaProperty>
#include <QRegularExpression>
#include <QSet>
#include <QTest>

#include "marathon-app-native/src/bluetooth.cxxqt.h"
#include "marathon-app-native/src/security.cxxqt.h"
#include "marathon-app-native/src/audio.cxxqt.h"
#include "marathon-app-native/src/display.cxxqt.h"
#include "marathon-app-native/src/modem.cxxqt.h"
#include "marathon-app-native/src/network.cxxqt.h"
#include "marathon-app-native/src/permissions.cxxqt.h"
#include "marathon-app-native/src/settings.cxxqt.h"
#include "marathon-app-native/src/power.cxxqt.h"
#include "managers/settingsmanager.h"

namespace {

    // NOLINTNEXTLINE(bugprone-throwing-static-initialization) QStringLiteral never allocates
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
        static const QRegularExpression keyProperty(R"re(property string key:([^\n]*))re");
        const QString picker  = read("apps/settings/pages/SoundPickerPage.qml");
        const QString keyLine = keyProperty.match(picker).captured(1);
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
    const QHash<QString, Consumer> &consumers() {
        static const QHash<QString, Consumer> table = {
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
        return table;
    }

    const QHash<QString, Consumer> &clientWriteConsumers() {
        static const QHash<QString, Consumer> table = {
            {"Display.brightness",
             {"crates/marathon-shell-native/src/display.rs", "fn set_brightness_from_user"}},
            {"Display.autoBrightnessEnabled",
             {"crates/marathon-shell-native/src/display.rs", "self.auto_brightness && self.screen_on"}},
            {"Display.rotationLocked", {"shell/main.cpp", "rotationManager->lockOrientation"}},
            {"Bluetooth.enabled", {"shell/src/managers/bluetoothmanager.cpp", "\"Powered\""}},
        };
        return table;
    }

    // Written but not yet acted on; each is an open audit finding.
    const QHash<QString, QString> &knownGaps() {
        static const QHash<QString, QString> table;
        return table;
    }

    bool hasWritableProperty(const QMetaObject &meta, const QString &name) {
        const int i = meta.indexOfProperty(name.toUtf8().constData());
        return i >= 0 && meta.property(i).isWritable() && meta.property(i).hasNotifySignal();
    }

    // Marathon.Platform names the Settings app uses and the runner clients behind them.
    const QHash<QString, const QMetaObject *> &platformClients() {
        static const QHash<QString, const QMetaObject *> table = {
            {"Settings", &marathon::platform::Settings::staticMetaObject},
            {"Display", &marathon::platform::Display::staticMetaObject},
            {"Bluetooth", &marathon::platform::Bluetooth::staticMetaObject},
            {"Network", &marathon::platform::Network::staticMetaObject},
            {"Power", &marathon::platform::Power::staticMetaObject},
            {"Audio", &Audio::staticMetaObject},
            {"Security", &marathon::platform::Security::staticMetaObject},
            {"Modem", &marathon::platform::Modem::staticMetaObject},
            {"Permissions", &marathon::platform::Permissions::staticMetaObject},
        };
        return table;
    }

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
        QVERIFY2(hasWritableProperty(marathon::platform::Settings::staticMetaObject, key),
                 "not a writable, notifying property on the runner's Settings");
        QVERIFY2(hasWritableProperty(SettingsManager::staticMetaObject, key),
                 "not a writable, notifying property on the shell's SettingsManager");

        const QString service = read("shell/src/ipc/shellservices.cpp");
        QVERIFY2(service.contains(QStringLiteral("name == \"%1\"").arg(key)),
                 "no SetProperty case in shellservices.cpp");
        QVERIFY2(service.contains(QStringLiteral("{\"%1\", m_settings->").arg(key)),
                 "not in the Settings GetState snapshot");

        if (knownGaps().contains(key))
            QSKIP(qPrintable(QStringLiteral("no shell consumer yet (%1)").arg(knownGaps()[key])));
        QVERIFY2(consumers().contains(key), "no shell consumer listed in consumers()");
        const Consumer c = consumers().value(key);
        QVERIFY2(read(QString::fromLatin1(c.file)).contains(QString::fromLatin1(c.token)),
                 qPrintable(QStringLiteral("%1 no longer reads it").arg(c.file)));
    }

    // A keyboard setting the shell never reads is a dead control.
    void keyboardSettingsAreRead() {
        for (const QMetaObject *meta :
             {&SettingsManager::staticMetaObject, &marathon::platform::Settings::staticMetaObject}) {
            for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
                const QString name = QString::fromLatin1(meta->property(i).name());
                if (name.startsWith(QLatin1String("keyboard")))
                    QVERIFY2(consumers().contains(name),
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
                QVERIFY2(hasWritableProperty(*platformClients().value(name), key), qPrintable(full));
                QVERIFY2(clientWriteConsumers().contains(full),
                         qPrintable(full + QStringLiteral(": no shell consumer listed")));
                const Consumer c = clientWriteConsumers().value(full);
                QVERIFY2(read(QString::fromLatin1(c.file)).contains(QString::fromLatin1(c.token)),
                         qPrintable(full));
            }
        }
    }

    // Each value an app's Audio client reads must be in the shell's Audio
    // snapshot, and the profile pushed again when it changes.
    void audioStateCarriesWhatAppsRead() {
        const QSet<QString> keys =
            matches(read("crates/marathon-app-native/src/audio.rs"), R"re(get\(&s, "(\w+)"\))re");
        QVERIFY(keys.contains(QStringLiteral("audioProfile")));
        const QString   service = read("shell/src/ipc/shellservices.cpp");
        const qsizetype begin   = service.indexOf(QLatin1String("AudioObject::AudioObject("));
        const qsizetype end = service.indexOf(QLatin1String("QVariantMap AudioObject::GetState"));
        QVERIFY(begin >= 0 && end > begin);
        const QString audio = service.mid(begin, end - begin);
        for (const QString &key : keys)
            QVERIFY2(audio.contains(QStringLiteral("{\"%1\",").arg(key)),
                     qPrintable(key + QStringLiteral(": not in the Audio GetState snapshot")));
        QVERIFY(audio.contains(
            QLatin1String("&AudioPolicyController::audioProfileChanged, this, push")));
    }

    void platformMembersExist_data() {
        QTest::addColumn<QString>("name");
        for (auto it = platformClients().cbegin(); it != platformClients().cend(); ++it)
            QTest::newRow(qPrintable(it.key())) << it.key();
    }

    // The tests' hand-written stubs can't catch a page using a member the real client lacks.
    void platformMembersExist() {
        QFETCH(QString, name);
        const QMetaObject  *meta = platformClients().value(name);
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
                    .contains(R"(exposeClient<marathon::platform::Modem>(ctx, "ModemManagerCpp")"));
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
