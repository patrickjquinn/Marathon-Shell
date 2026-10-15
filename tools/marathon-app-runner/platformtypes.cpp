#include "platformtypes.h"

#include <QQmlContext>
#include <QQmlEngine>

QHash<QString, QString> platformTypeNames() {
    return {
        {QStringLiteral("PermissionManager"), QStringLiteral("Permissions")},
        {QStringLiteral("AppLifecycleManager"), QStringLiteral("Lifecycle")},
        {QStringLiteral("NavigationService"), QStringLiteral("Navigation")},
        {QStringLiteral("ContactsManager"), QStringLiteral("Contacts")},
        {QStringLiteral("CallHistoryManager"), QStringLiteral("CallHistory")},
        {QStringLiteral("TelephonyService"), QStringLiteral("Telephony")},
        {QStringLiteral("SMSService"), QStringLiteral("Sms")},
        {QStringLiteral("MediaLibraryManager"), QStringLiteral("MediaLibrary")},
        {QStringLiteral("CalendarManager"), QStringLiteral("Calendar")},
        {QStringLiteral("WorldClockHelper"), QStringLiteral("WorldClock")},
        {QStringLiteral("SensorService"), QStringLiteral("Sensors")},
        {QStringLiteral("HapticService"), QStringLiteral("Haptics")},
        {QStringLiteral("LocationService"), QStringLiteral("Location")},
        {QStringLiteral("AlarmService"), QStringLiteral("Alarms")},
        {QStringLiteral("SettingsManagerCpp"), QStringLiteral("Settings")},
        {QStringLiteral("NetworkManagerCpp"), QStringLiteral("Network")},
        {QStringLiteral("ModemManagerCpp"), QStringLiteral("Modem")},
        {QStringLiteral("BluetoothManagerCpp"), QStringLiteral("Bluetooth")},
        {QStringLiteral("DisplayManagerCpp"), QStringLiteral("Display")},
        {QStringLiteral("PowerManagerService"), QStringLiteral("Power")},
        {QStringLiteral("AudioManagerCpp"), QStringLiteral("Audio")},
        {QStringLiteral("SecurityManagerCpp"), QStringLiteral("Security")},
        {QStringLiteral("UpdateService"), QStringLiteral("Updates")},
        {QStringLiteral("DavSyncEngine"), QStringLiteral("DavSync")},
        {QStringLiteral("AppStoreService"), QStringLiteral("AppStore")},
        {QStringLiteral("WallpaperStore"), QStringLiteral("Wallpapers")},
        {QStringLiteral("MarathonAppRegistry"), QStringLiteral("Apps")},
        {QStringLiteral("MarathonAppInstaller"), QStringLiteral("AppInstaller")},
    };
}

QStringList registerPlatformTypes(QQmlContext *context) {
    QStringList registered;
    const auto  names = platformTypeNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it) {
        auto *object = context->contextProperty(it.key()).value<QObject *>();
        if (!object)
            continue;
        qmlRegisterSingletonInstance("Marathon.Platform", 1, 0, qPrintable(it.value()), object);
        registered << it.value();
    }
    return registered;
}
