#pragma once

// Marathon.Platform's types for qmllint. The runner registers these at
// runtime (platformtypes.cpp); this header is only moc'd, never compiled
// into the runner. Names match platformTypeNames().

#include <QtQml/qqmlregistration.h>

#include "calendarmanagercpp.h"
#include "ipc/shellipcclients.h"
#include "marathon-app-native/src/alarms.cxxqt.h"
#include "marathon-app-native/src/contacts.cxxqt.h"
#include "marathon-app-native/src/display.cxxqt.h"
#include "marathon-app-native/src/location.cxxqt.h"
#include "marathon-app-native/src/modem.cxxqt.h"
#include "marathon-app-native/src/network.cxxqt.h"
#include "marathon-app-native/src/permissions.cxxqt.h"
#include "marathon-app-native/src/power.cxxqt.h"
#include "marathon-app-native/src/sensors.cxxqt.h"
#include "marathon-app-native/src/settings.cxxqt.h"
#include "marathon-app-native/src/telephony.cxxqt.h"
#include "marathonappregistry.h"
#include "wallpaperclient.h"
#include "worldclockhelper.h"

struct PlatformPermissions {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Permissions)
    QML_NAMED_ELEMENT(Permissions)
    QML_SINGLETON
};

struct PlatformLifecycle {
    Q_GADGET
    QML_FOREIGN(AppLifecycleClient)
    QML_NAMED_ELEMENT(Lifecycle)
    QML_SINGLETON
};

struct PlatformNavigation {
    Q_GADGET
    QML_FOREIGN(NavigationClient)
    QML_NAMED_ELEMENT(Navigation)
    QML_SINGLETON
};

struct PlatformContacts {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Contacts)
    QML_NAMED_ELEMENT(Contacts)
    QML_SINGLETON
};

struct PlatformCallHistory {
    Q_GADGET
    QML_FOREIGN(CallHistoryClient)
    QML_NAMED_ELEMENT(CallHistory)
    QML_SINGLETON
};

struct PlatformTelephony {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Telephony)
    QML_NAMED_ELEMENT(Telephony)
    QML_SINGLETON
};

struct PlatformSms {
    Q_GADGET
    QML_FOREIGN(SmsClient)
    QML_NAMED_ELEMENT(Sms)
    QML_SINGLETON
};

struct PlatformMediaLibrary {
    Q_GADGET
    QML_FOREIGN(MediaLibraryClient)
    QML_NAMED_ELEMENT(MediaLibrary)
    QML_SINGLETON
};

struct PlatformCalendar {
    Q_GADGET
    QML_FOREIGN(CalendarManagerCpp)
    QML_NAMED_ELEMENT(Calendar)
    QML_SINGLETON
};

struct PlatformWorldClock {
    Q_GADGET
    QML_FOREIGN(WorldClockHelper)
    QML_NAMED_ELEMENT(WorldClock)
    QML_SINGLETON
};

struct PlatformSensors {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Sensors)
    QML_NAMED_ELEMENT(Sensors)
    QML_SINGLETON
};

struct PlatformHaptics {
    Q_GADGET
    QML_FOREIGN(HapticClient)
    QML_NAMED_ELEMENT(Haptics)
    QML_SINGLETON
};

struct PlatformLocation {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Location)
    QML_NAMED_ELEMENT(Location)
    QML_SINGLETON
};

struct PlatformAlarms {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Alarms)
    QML_NAMED_ELEMENT(Alarms)
    QML_SINGLETON
};

struct PlatformSettings {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Settings)
    QML_NAMED_ELEMENT(Settings)
    QML_SINGLETON
};

struct PlatformNetwork {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Network)
    QML_NAMED_ELEMENT(Network)
    QML_SINGLETON
};

struct PlatformModem {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Modem)
    QML_NAMED_ELEMENT(Modem)
    QML_SINGLETON
};

struct PlatformBluetooth {
    Q_GADGET
    QML_FOREIGN(BluetoothClient)
    QML_NAMED_ELEMENT(Bluetooth)
    QML_SINGLETON
};

struct PlatformDisplay {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Display)
    QML_NAMED_ELEMENT(Display)
    QML_SINGLETON
};

struct PlatformPower {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Power)
    QML_NAMED_ELEMENT(Power)
    QML_SINGLETON
};

struct PlatformAudio {
    Q_GADGET
    QML_FOREIGN(AudioClient)
    QML_NAMED_ELEMENT(Audio)
    QML_SINGLETON
};

struct PlatformSecurity {
    Q_GADGET
    QML_FOREIGN(SecurityClient)
    QML_NAMED_ELEMENT(Security)
    QML_SINGLETON
};

struct PlatformUpdates {
    Q_GADGET
    QML_FOREIGN(UpdateClient)
    QML_NAMED_ELEMENT(Updates)
    QML_SINGLETON
};

struct PlatformDavSync {
    Q_GADGET
    QML_FOREIGN(DavClient)
    QML_NAMED_ELEMENT(DavSync)
    QML_SINGLETON
};

struct PlatformAppStore {
    Q_GADGET
    QML_FOREIGN(AppStoreClient)
    QML_NAMED_ELEMENT(AppStore)
    QML_SINGLETON
};

struct PlatformWallpapers {
    Q_GADGET
    QML_FOREIGN(WallpaperClient)
    QML_NAMED_ELEMENT(Wallpapers)
    QML_SINGLETON
};

struct PlatformApps {
    Q_GADGET
    QML_FOREIGN(MarathonAppRegistry)
    QML_NAMED_ELEMENT(Apps)
    QML_SINGLETON
};

struct PlatformAppInstaller {
    Q_GADGET
    QML_FOREIGN(AppInstallerClient)
    QML_NAMED_ELEMENT(AppInstaller)
    QML_SINGLETON
};

struct PlatformRemoteAudioStreamModel {
    Q_GADGET
    QML_FOREIGN(RemoteAudioStreamModel)
    QML_ANONYMOUS
};
