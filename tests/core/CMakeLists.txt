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

# Every device and personal-data D-Bus method checks a permission
add_executable(test_core_ipcgates test_ipcgates.cpp)
target_link_libraries(test_core_ipcgates Qt6::Test Qt6::Core)
target_compile_definitions(test_core_ipcgates PRIVATE MARATHON_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
add_test(NAME Core_IpcGates COMMAND test_core_ipcgates)

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
    ../../marathon-core/src/marathonappverifier.cpp
)
target_link_libraries(test_core_appscanner Qt6::Test Qt6::Core marathon_core_native)
target_include_directories(test_core_appscanner PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppScanner COMMAND test_core_appscanner)

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
    ../../marathon-core/src/marathonappverifier.cpp
)
target_link_libraries(test_core_apptoolkit Qt6::Test Qt6::Core marathon_core_native)
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
add_executable(test_core_ambienceclient test_ambienceclient.cpp)
set_target_properties(test_core_ambienceclient PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_ambienceclient Qt6::Test Qt6::Core Qt6::DBus marathon_app_native)
add_test(NAME Core_AmbienceClient COMMAND test_core_ambienceclient)
set_tests_properties(Core_KeelHost PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Marathon.Platform: the runner's service clients under their QML names
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
    ../../tools/marathon-app-runner/ipc/dbusnormalize.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
)
target_link_libraries(test_core_settingscontract Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml MarathonCore marathon_app_native)
target_include_directories(test_core_settingscontract PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-services/src
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src
)
target_compile_definitions(test_core_settingscontract PRIVATE MARATHON_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
add_test(NAME Core_SettingsContract COMMAND test_core_settingscontract)

# Runner IPC clients hand QML plain maps and lists, not QDBusArgument
add_executable(test_core_ipcclientnormalize
    test_ipcclientnormalize.cpp
)
set_target_properties(test_core_ipcclientnormalize PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_ipcclientnormalize Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml MarathonCore marathon_app_native)
target_include_directories(test_core_ipcclientnormalize PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-services/src
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Core_IpcClientNormalize COMMAND test_core_ipcclientnormalize)

# Runner clients read again once the user allows their permission
add_executable(test_core_grantrefresh test_grantrefresh.cpp)
set_target_properties(test_core_grantrefresh PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_grantrefresh Qt6::Test Qt6::Core Qt6::DBus marathon_app_native)
add_test(NAME Core_GrantRefresh COMMAND test_core_grantrefresh)

# Settings uninstalls through the shell, over the shell's real installer
add_executable(test_core_appinstallerclient
    test_appinstallerclient.cpp
)
set_target_properties(test_core_appinstallerclient PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_appinstallerclient Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml MarathonCore marathon_app_native)
target_include_directories(test_core_appinstallerclient PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-services/src
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Core_AppInstallerClient COMMAND test_core_appinstallerclient)

# The runner's Power client reports whether the shell woke the screen
add_executable(test_core_powerclient test_powerclient.cpp)
set_target_properties(test_core_powerclient PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_powerclient Qt6::Test Qt6::Core Qt6::DBus marathon_app_native)
add_test(NAME Core_PowerClient COMMAND test_core_powerclient)

# The runner's Power and Display clients say when the shell refuses them
add_executable(test_core_refusedclients
    test_refusedclients.cpp
)
set_target_properties(test_core_refusedclients PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_refusedclients Qt6::Test Qt6::Core Qt6::DBus marathon_app_native)
add_test(NAME Core_RefusedClients COMMAND test_core_refusedclients)

# The runner's Location client follows the shared session's state
add_executable(test_core_locationclient test_locationclient.cpp)
set_target_properties(test_core_locationclient PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_locationclient Qt6::Test Qt6::Core Qt6::DBus marathon_app_native)
add_test(NAME Core_LocationClient COMMAND test_core_locationclient)

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

# The runner's Sms client: MMS parts as descriptors, attachments cached
if(DBUS_RUN_SESSION)
    add_executable(test_core_smsclient test_smsclient.cpp)
    target_link_libraries(test_core_smsclient Qt6::Test Qt6::Core Qt6::DBus marathon_app_native)
    add_test(NAME Core_SmsClient COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_core_smsclient>)
endif()

# Calls: how each one ends up in the call log
add_executable(test_core_telephonyservice test_telephonyservice.cpp)
target_link_libraries(test_core_telephonyservice Qt6::Test Qt6::Core Qt6::DBus marathon_shell_native)
add_test(NAME Core_TelephonyService COMMAND test_core_telephonyservice)

# Sound names format locally, shared by the shell and the app runner
add_executable(test_core_soundname test_soundname.cpp)
set_target_properties(test_core_soundname PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_soundname Qt6::Test Qt6::Core)
target_include_directories(test_core_soundname PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_SoundName COMMAND test_core_soundname)


# Wake touch hygiene: no touch for 100 ms after wake, none until a fresh one
add_executable(test_core_waketouchfilter
    test_waketouchfilter.cpp
    ../../shell/src/services/waketouchfilter.cpp
)
set_target_properties(test_core_waketouchfilter PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_waketouchfilter Qt6::Test Qt6::Gui Qt6::Qml Qt6::Quick)
target_include_directories(test_core_waketouchfilter PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_WakeTouchFilter COMMAND test_core_waketouchfilter)
set_tests_properties(Core_WakeTouchFilter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
