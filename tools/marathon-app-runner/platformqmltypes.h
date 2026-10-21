#pragma once

// Marathon.Platform's types for qmllint. The runner registers these at
// runtime (platformtypes.cpp); this header is only moc'd, never compiled
// into the runner. Names match platformTypeNames().

#include <QtQml/qqmlregistration.h>

#include "marathon-app-native/src/calendar.cxxqt.h"
#include "marathon-app-native/src/alarms.cxxqt.h"
#include "marathon-app-native/src/audio.cxxqt.h"
#include "marathon-app-native/src/bluetooth.cxxqt.h"
#include "marathon-app-native/src/contacts.cxxqt.h"
#include "marathon-app-native/src/dav.cxxqt.h"
#include "marathon-app-native/src/display.cxxqt.h"
#include "marathon-app-native/src/haptics.cxxqt.h"
#include "marathon-app-native/src/history.cxxqt.h"
#include "marathon-app-native/src/lifecycle.cxxqt.h"
#include "marathon-app-native/src/location.cxxqt.h"
#include "marathon-app-native/src/mail.cxxqt.h"
#include "marathon-app-native/src/media.cxxqt.h"
#include "marathon-app-native/src/modem.cxxqt.h"
#include "marathon-app-native/src/navigation.cxxqt.h"
#include "marathon-app-native/src/network.cxxqt.h"
#include "marathon-app-native/src/notifications.cxxqt.h"
#include "marathon-app-native/src/permissions.cxxqt.h"
#include "marathon-app-native/src/power.cxxqt.h"
#include "marathon-app-native/src/security.cxxqt.h"
#include "marathon-app-native/src/sensors.cxxqt.h"
#include "marathon-app-native/src/settings.cxxqt.h"
#include "marathon-app-native/src/sms.cxxqt.h"
#include "marathon-app-native/src/store.cxxqt.h"
#include "marathon-app-native/src/stores.cxxqt.h"
#include "marathon-app-native/src/telephony.cxxqt.h"
#include "marathon-app-native/src/updates.cxxqt.h"
#include "marathon-app-native/src/wallpapers.cxxqt.h"
#include "marathon-app-native/src/apps.cxxqt.h"
#include "marathon-app-native/src/world_clock.cxxqt.h"

struct PlatformPermissions {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Permissions)
    QML_NAMED_ELEMENT(Permissions)
    QML_SINGLETON
};

struct PlatformLifecycle {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Lifecycle)
    QML_NAMED_ELEMENT(Lifecycle)
    QML_SINGLETON
};

struct PlatformNavigation {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Navigation)
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
    QML_FOREIGN(marathon::platform::CallHistory)
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
    QML_FOREIGN(marathon::platform::Sms)
    QML_NAMED_ELEMENT(Sms)
    QML_SINGLETON
};

struct PlatformMediaLibrary {
    Q_GADGET
    QML_FOREIGN(marathon::platform::MediaLibrary)
    QML_NAMED_ELEMENT(MediaLibrary)
    QML_SINGLETON
};

struct PlatformCalendar {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Calendar)
    QML_NAMED_ELEMENT(Calendar)
    QML_SINGLETON
};

struct PlatformWorldClock {
    Q_GADGET
    QML_FOREIGN(marathon::platform::WorldClock)
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
    QML_FOREIGN(marathon::platform::Haptics)
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
    QML_FOREIGN(marathon::platform::Bluetooth)
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
    QML_FOREIGN(Audio)
    QML_NAMED_ELEMENT(Audio)
    QML_SINGLETON
};

struct PlatformSecurity {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Security)
    QML_NAMED_ELEMENT(Security)
    QML_SINGLETON
};

struct PlatformUpdates {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Updates)
    QML_NAMED_ELEMENT(Updates)
    QML_SINGLETON
};

struct PlatformDavSync {
    Q_GADGET
    QML_FOREIGN(marathon::platform::DavSync)
    QML_NAMED_ELEMENT(DavSync)
    QML_SINGLETON
};

struct PlatformWallpapers {
    Q_GADGET
    QML_FOREIGN(marathon::platform::Wallpapers)
    QML_NAMED_ELEMENT(Wallpapers)
    QML_SINGLETON
};

struct PlatformApps {
    Q_GADGET
    QML_FOREIGN(AppRegistry)
    QML_NAMED_ELEMENT(Apps)
    QML_SINGLETON
};

struct PlatformAppInstaller {
    Q_GADGET
    QML_FOREIGN(marathon::platform::AppInstaller)
    QML_NAMED_ELEMENT(AppInstaller)
    QML_SINGLETON
};

struct PlatformAudioStreams {
    Q_GADGET
    QML_FOREIGN(AudioStreams)
    QML_ANONYMOUS
};

struct PlatformMailList {
    Q_GADGET
    QML_FOREIGN(MailList)
    QML_ANONYMOUS
};
