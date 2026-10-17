# Marathon Core Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core DBus Gui Network)

# AppRegistry tests (pure data model, no external deps)
add_executable(test_core_appregistry
    test_appregistry.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_core_appregistry Qt6::Test Qt6::Core)
target_include_directories(test_core_appregistry PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppRegistry COMMAND test_core_appregistry)

# Which installed app a notification belongs to
add_executable(test_core_notificationtarget
    test_notificationtarget.cpp
    ../../shell/src/services/notificationtarget.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_core_notificationtarget Qt6::Test Qt6::Core)
target_include_directories(test_core_notificationtarget PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Core_NotificationTarget COMMAND test_core_notificationtarget)

# AppPackager tests (validation, round-trip, archive symlink refusal)
add_executable(test_core_apppackager
    test_apppackager.cpp
    ../../marathon-core/src/marathonapppackager.cpp
)
target_link_libraries(test_core_apppackager Qt6::Test Qt6::Core marathon_core_native)
target_include_directories(test_core_apppackager PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppPackager COMMAND test_core_apppackager)

# Manifest lint and permission vocabulary through the C++ API
add_executable(test_core_manifest
    test_manifest.cpp
    ../../marathon-core/src/marathonmanifest.cpp
)
target_link_libraries(test_core_manifest Qt6::Test Qt6::Core marathon_core_native)
target_include_directories(test_core_manifest PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_Manifest COMMAND test_core_manifest)

# PermissionManager tests (grant/deny/revoke logic)
add_executable(test_core_permissionmanager
    test_permissionmanager.cpp
    ../../shell/src/marathonpermissionmanager.cpp
    ../../shell/src/components/portalmanager.cpp
    ../../marathon-core/src/marathonmanifest.cpp
)
target_link_libraries(test_core_permissionmanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml marathon_core_native)
target_include_directories(test_core_permissionmanager PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src
    ${CMAKE_SOURCE_DIR}/shell/src/components
)
add_test(NAME Core_PermissionManager COMMAND test_core_permissionmanager)

# Permissions1 authorisation: self-only, except Settings
add_executable(test_core_permissionauth test_permissionauth.cpp)
target_link_libraries(test_core_permissionauth Qt6::Test Qt6::Core)
target_include_directories(test_core_permissionauth PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_PermissionAuth COMMAND test_core_permissionauth)

# D-Bus callers that are installed session services (shell/src/ipc/servicecaller.h)
add_executable(test_core_servicecaller test_servicecaller.cpp)
target_link_libraries(test_core_servicecaller Qt6::Test Qt6::Core)
target_include_directories(test_core_servicecaller PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_ServiceCaller COMMAND test_core_servicecaller)

# AppInstaller security tests (path traversal, uninstall protection)
add_executable(test_core_installer_security
    test_installer_security.cpp
    ../../marathon-core/src/marathonappinstaller.cpp
    ../../marathon-core/src/marathonapppackager.cpp
    ../../marathon-core/src/marathonappverifier.cpp
    ../../marathon-core/src/marathonappregistry.cpp
    ../../marathon-core/src/marathonappscanner.cpp
)
target_link_libraries(test_core_installer_security Qt6::Test Qt6::Core marathon_core_native)
target_include_directories(test_core_installer_security PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_InstallerSecurity COMMAND test_core_installer_security)

# AppScanner tests (manifest parsing, signal contracts, validation)
add_executable(test_core_appscanner
    test_appscanner.cpp
    ../../marathon-core/src/marathonappscanner.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_core_appscanner Qt6::Test Qt6::Core)
target_include_directories(test_core_appscanner PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppScanner COMMAND test_core_appscanner)

# UpdateService state machine and download gating; sysupdated's AppStream parse
add_executable(test_core_updateservice
    test_updateservice.cpp
    ../../shell/src/services/updateservice.cpp
    ../../shell/src/services/sysupdatebackend.cpp
)
target_link_libraries(test_core_updateservice Qt6::Test Qt6::Core Qt6::DBus Qt6::Network)
target_include_directories(test_core_updateservice PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Core_UpdateService COMMAND test_core_updateservice)

# DesktopFileParser tests (exec cleaning, .desktop parsing, icon resolution)
add_executable(test_core_desktopfileparser
    test_desktopfileparser.cpp
    ../../shell/src/components/desktopfileparser.cpp
)
target_link_libraries(test_core_desktopfileparser Qt6::Test Qt6::Core)
target_include_directories(test_core_desktopfileparser PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/components
)
add_test(NAME Core_DesktopFileParser COMMAND test_core_desktopfileparser)

# Pool keepalive page touching (marathon-app-runner)
add_executable(test_core_pagetouch
    test_pagetouch.cpp
    ../../tools/marathon-app-runner/pagetouch.cpp
)
target_link_libraries(test_core_pagetouch Qt6::Test Qt6::Core)
target_include_directories(test_core_pagetouch PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_PageTouch COMMAND test_core_pagetouch)

# Manifest toolkit field (keel by default, marathonui for legacy apps)
add_executable(test_core_apptoolkit
    test_apptoolkit.cpp
    ../../marathon-core/src/marathonappscanner.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_core_apptoolkit Qt6::Test Qt6::Core)
target_include_directories(test_core_apptoolkit PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppToolkit COMMAND test_core_apptoolkit)

# Keel host protocol server (marathon-app-runner)
add_executable(test_core_keelhost
    test_keelhost.cpp
    ../../tools/marathon-app-runner/keelhost.cpp
)
target_link_libraries(test_core_keelhost Qt6::Test Qt6::Core Qt6::DBus Qt6::Gui)
target_include_directories(test_core_keelhost PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_KeelHost COMMAND test_core_keelhost)

# Ambience relay client (marathon-app-runner)
add_executable(test_core_ambienceclient
    test_ambienceclient.cpp
    ../../tools/marathon-app-runner/ambienceclient.cpp
)
target_link_libraries(test_core_ambienceclient Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_core_ambienceclient PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_AmbienceClient COMMAND test_core_ambienceclient)
set_tests_properties(Core_KeelHost PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Marathon.Platform: the runner's service clients under Sailfish-style names
find_package(Qt6 REQUIRED COMPONENTS Qml)
add_executable(test_core_platformtypes
    test_platformtypes.cpp
    ../../tools/marathon-app-runner/platformtypes.cpp
)
target_link_libraries(test_core_platformtypes Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_core_platformtypes PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_PlatformTypes COMMAND test_core_platformtypes)

# A native Keel app (rebuilt SailfishApp) run under a Keel host
add_executable(test_core_hostedapp
    test_hostedapp.cpp
    ../../tools/marathon-app-runner/hostedapp.cpp
    ../../tools/marathon-app-runner/keelhost.cpp
)
target_link_libraries(test_core_hostedapp Qt6::Test Qt6::Core Qt6::DBus Qt6::Gui)
target_include_directories(test_core_hostedapp PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_HostedApp COMMAND test_core_hostedapp)
set_tests_properties(Core_HostedApp PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The shell's lifecycle calls to a hosted app
add_executable(test_core_hostlifecycle
    test_hostlifecycle.cpp
    ../../tools/marathon-app-runner/hostlifecycle.cpp
    ../../tools/marathon-app-runner/keelhost.cpp
)
target_link_libraries(test_core_hostlifecycle Qt6::Test Qt6::Core Qt6::DBus Qt6::Gui)
target_include_directories(test_core_hostlifecycle PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_HostLifecycle COMMAND test_core_hostlifecycle)

# Wallpapers for the Settings app (Marathon.Platform Wallpapers)
add_executable(test_core_wallpaperclient
    test_wallpaperclient.cpp
    ../../tools/marathon-app-runner/wallpaperclient.cpp
)
target_link_libraries(test_core_wallpaperclient Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_core_wallpaperclient PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_WallpaperClient COMMAND test_core_wallpaperclient)

# Sailjail permissions as a bwrap sandbox for Sailfish apps
add_executable(test_core_sailjail test_sailjail.cpp ../../tools/marathon-app-runner/sailjail.cpp)
target_link_libraries(test_core_sailjail Qt6::Test Qt6::Core)
target_include_directories(test_core_sailjail PRIVATE ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner)
add_test(NAME Core_Sailjail COMMAND test_core_sailjail)

# App signature trust: only keys in trusted-keys verify
add_executable(test_core_appverifier test_appverifier.cpp ../../marathon-core/src/marathonappverifier.cpp)
target_link_libraries(test_core_appverifier Qt6::Test Qt6::Core marathon_core_native)
target_include_directories(test_core_appverifier PRIVATE ${CMAKE_SOURCE_DIR}/marathon-core/src)
add_test(NAME Core_AppVerifier COMMAND test_core_appverifier)

# Every setting the Settings app writes reaches the shell and has a reader
find_package(Qt6 REQUIRED COMPONENTS DBus Qml)
add_executable(test_core_settingscontract
    test_settingscontract.cpp
    ../../tools/marathon-app-runner/ipc/shellipcclients.cpp
    ../../tools/marathon-app-runner/ipc/dbusnormalize.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
target_link_libraries(test_core_settingscontract Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_settingscontract PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/shell/src
)
target_compile_definitions(test_core_settingscontract PRIVATE MARATHON_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
add_test(NAME Core_SettingsContract COMMAND test_core_settingscontract)

# Runner IPC clients hand QML plain maps and lists, not QDBusArgument
add_executable(test_core_ipcclientnormalize
    test_ipcclientnormalize.cpp
    ../../tools/marathon-app-runner/ipc/shellipcclients.cpp
    ../../tools/marathon-app-runner/ipc/dbusnormalize.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
set_target_properties(test_core_ipcclientnormalize PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_ipcclientnormalize Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_ipcclientnormalize PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Core_IpcClientNormalize COMMAND test_core_ipcclientnormalize)

# The runner's Power client reports whether the shell woke the screen
add_executable(test_core_powerclient
    test_powerclient.cpp
    ../../tools/marathon-app-runner/ipc/shellipcclients.cpp
    ../../tools/marathon-app-runner/ipc/dbusnormalize.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
set_target_properties(test_core_powerclient PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_powerclient Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_powerclient PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Core_PowerClient COMMAND test_core_powerclient)

# D-Bus reply containers normalize without demarshalling the wrong type
add_executable(test_core_dbusnormalize
    test_dbusnormalize.cpp
    ../../tools/marathon-app-runner/ipc/dbusnormalize.cpp
)
set_target_properties(test_core_dbusnormalize PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_dbusnormalize Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_core_dbusnormalize PRIVATE ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner)
add_test(NAME Core_DbusNormalize COMMAND test_core_dbusnormalize)

# WAKE_ON_KEY: a key wakes a blanked screen without reaching apps
add_executable(test_core_wakeonkeyfilter
    test_wakeonkeyfilter.cpp
    ../../shell/src/services/wakeonkeyfilter.cpp
)
set_target_properties(test_core_wakeonkeyfilter PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_wakeonkeyfilter Qt6::Test Qt6::Gui Qt6::GuiPrivate)
target_include_directories(test_core_wakeonkeyfilter PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_WakeOnKeyFilter COMMAND test_core_wakeonkeyfilter)
set_tests_properties(Core_WakeOnKeyFilter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The old auto-lock switch carried into the lock delay
add_executable(test_core_lockdelaymigration
    test_lockdelaymigration.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
target_link_libraries(test_core_lockdelaymigration Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_lockdelaymigration PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_LockDelayMigration COMMAND test_core_lockdelaymigration)

# New installs default to the Mývatn aurora; a chosen wallpaper stays
add_executable(test_core_defaultwallpaper
    test_defaultwallpaper.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/services/wallpaperstore.cpp
)
set_target_properties(test_core_defaultwallpaper PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_defaultwallpaper Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_defaultwallpaper PRIVATE ${CMAKE_SOURCE_DIR}/shell/src ${CMAKE_SOURCE_DIR}/shell)
add_test(NAME Core_DefaultWallpaper COMMAND test_core_defaultwallpaper)

# Unstorable settings values neither poison the file nor reach QML
add_executable(test_core_settingsstore
    test_settingsstore.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
set_target_properties(test_core_settingsstore PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_settingsstore Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_settingsstore PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_SettingsStore COMMAND test_core_settingsstore)

# Music library: scans and track loads run off the GUI thread
find_package(Qt6 REQUIRED COMPONENTS Sql)
add_executable(test_core_musiclibrary
    test_musiclibrary.cpp
    ../../marathon-services/src/musiclibrarymanager.cpp
)
target_link_libraries(test_core_musiclibrary Qt6::Test Qt6::Core Qt6::Sql)
target_include_directories(test_core_musiclibrary PRIVATE ${CMAKE_SOURCE_DIR}/marathon-services/src)
add_test(NAME Core_MusicLibrary COMMAND test_core_musiclibrary)

# Music's MPRIS publisher, on a private session bus
find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    find_package(Qt6 REQUIRED COMPONENTS DBus Qml)
    add_executable(test_core_mprisplayer
        test_mprisplayer.cpp
        ../../apps/music/src/MprisPlayer.cpp
        ../../apps/music/src/MprisPlayer.h
    )
    target_link_libraries(test_core_mprisplayer Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
    target_include_directories(test_core_mprisplayer PRIVATE ${CMAKE_SOURCE_DIR}/apps/music/src)
    add_test(NAME Core_MprisPlayer COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_core_mprisplayer>)
endif()

# Music album art: embedded art cached to disk, or a cover file beside the track
find_package(Qt6 REQUIRED COMPONENTS Gui Qml)
add_executable(test_core_musicartwork
    test_musicartwork.cpp
    ../../apps/music/src/Artwork.cpp
    ../../apps/music/src/Artwork.h
)
target_link_libraries(test_core_musicartwork Qt6::Test Qt6::Core Qt6::Gui Qt6::Qml)
target_include_directories(test_core_musicartwork PRIVATE ${CMAKE_SOURCE_DIR}/apps/music/src)
add_test(NAME Core_MusicArtwork COMMAND test_core_musicartwork)

# SMS storage: deleting one message from a thread
if(TARGET MarathonServices)
    add_executable(test_core_smsservice test_smsservice.cpp)
    target_link_libraries(test_core_smsservice Qt6::Test Qt6::Core Qt6::DBus Qt6::Sql MarathonServices)
    target_include_directories(test_core_smsservice PRIVATE ${CMAKE_SOURCE_DIR}/marathon-services/src)
    add_test(NAME Core_SmsService COMMAND test_core_smsservice)

    # Calls: how each one ends up in the call log
    add_executable(test_core_telephonyservice test_telephonyservice.cpp)
    target_link_libraries(test_core_telephonyservice Qt6::Test Qt6::Core Qt6::DBus MarathonServices)
    target_include_directories(test_core_telephonyservice PRIVATE ${CMAKE_SOURCE_DIR}/marathon-services/src)
    add_test(NAME Core_TelephonyService COMMAND test_core_telephonyservice)

    # DAV account secrets: keyring migration, retry and removal
    add_executable(test_core_davsecrets test_davsecrets.cpp)
    target_link_libraries(test_core_davsecrets Qt6::Test Qt6::Core Qt6::DBus Qt6::Network MarathonServices)
    add_test(NAME Core_DavSecrets COMMAND test_core_davsecrets)
endif()

# Sound names format locally, shared by the shell and the app runner
add_executable(test_core_soundname test_soundname.cpp)
set_target_properties(test_core_soundname PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_soundname Qt6::Test Qt6::Core)
target_include_directories(test_core_soundname PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_SoundName COMMAND test_core_soundname)

# The shell's client of Shipwright Pilot's pilotd
add_executable(test_core_pilotclient test_pilotclient.cpp ../../shell/src/services/pilotclient.cpp)
find_package(Qt6 REQUIRED COMPONENTS Qml)
target_link_libraries(test_core_pilotclient Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_pilotclient PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Core_PilotClient COMMAND test_core_pilotclient)

# The shell's client of marathon-weatherd
add_executable(test_core_weatherclient test_weatherclient.cpp ../../shell/src/services/weatherclient.cpp)
target_link_libraries(test_core_weatherclient Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_weatherclient PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Core_WeatherClient COMMAND test_core_weatherclient)

# The shell as GeoClue's agent
add_executable(test_core_geoclueagent test_geoclueagent.cpp ../../shell/src/managers/geoclueagent.cpp)
target_link_libraries(test_core_geoclueagent Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_core_geoclueagent PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers)
add_test(NAME Core_GeoClueAgent COMMAND test_core_geoclueagent)

# Automatic time zone: nearest zone.tab city to the location fix
add_executable(test_core_automatictimezone
    test_automatictimezone.cpp
    ../../shell/src/services/automatictimezone.cpp
    ../../shell/src/managers/locationmanager.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
set_target_properties(test_core_automatictimezone PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_automatictimezone Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_automatictimezone PRIVATE ${CMAKE_SOURCE_DIR}/shell/src ${CMAKE_SOURCE_DIR}/shell)
add_test(NAME Core_AutomaticTimeZone COMMAND test_core_automatictimezone)

# Wake touch hygiene: no touch for 100 ms after wake, none until a fresh one
add_executable(test_core_waketouchfilter
    test_waketouchfilter.cpp
    ../../shell/src/services/waketouchfilter.cpp
)
set_target_properties(test_core_waketouchfilter PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_waketouchfilter Qt6::Test Qt6::Gui)
target_include_directories(test_core_waketouchfilter PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_WakeTouchFilter COMMAND test_core_waketouchfilter)
set_tests_properties(Core_WakeTouchFilter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
