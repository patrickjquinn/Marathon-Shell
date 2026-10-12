# Marathon Core Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core DBus Gui)

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

# AppPackager tests (validation + round-trip with zip/unzip)
add_executable(test_core_apppackager
    test_apppackager.cpp
    ../../marathon-core/src/marathonapppackager.cpp
)
target_link_libraries(test_core_apppackager Qt6::Test Qt6::Core)
target_include_directories(test_core_apppackager PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppPackager COMMAND test_core_apppackager)

# PermissionManager tests (grant/deny/revoke logic)
add_executable(test_core_permissionmanager
    test_permissionmanager.cpp
    ../../shell/src/marathonpermissionmanager.cpp
    ../../shell/src/components/portalmanager.cpp
)
target_link_libraries(test_core_permissionmanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_permissionmanager PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src
    ${CMAKE_SOURCE_DIR}/shell/src/components
)
add_test(NAME Core_PermissionManager COMMAND test_core_permissionmanager)

# Permissions1 authorisation: self-only, except Settings
add_executable(test_core_permissionauth test_permissionauth.cpp)
target_link_libraries(test_core_permissionauth Qt6::Test Qt6::Core)
target_include_directories(test_core_permissionauth PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_PermissionAuth COMMAND test_core_permissionauth)

# AppInstaller security tests (path traversal, uninstall protection)
add_executable(test_core_installer_security
    test_installer_security.cpp
    ../../marathon-core/src/marathonappinstaller.cpp
    ../../marathon-core/src/marathonapppackager.cpp
    ../../marathon-core/src/marathonappverifier.cpp
    ../../marathon-core/src/marathonappregistry.cpp
    ../../marathon-core/src/marathonappscanner.cpp
)
target_link_libraries(test_core_installer_security Qt6::Test Qt6::Core)
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
target_link_libraries(test_core_appverifier Qt6::Test Qt6::Core)
target_include_directories(test_core_appverifier PRIVATE ${CMAKE_SOURCE_DIR}/marathon-core/src)
add_test(NAME Core_AppVerifier COMMAND test_core_appverifier)

# Every setting the Settings app writes reaches the shell and has a reader
find_package(Qt6 REQUIRED COMPONENTS DBus Qml)
add_executable(test_core_settingscontract
    test_settingscontract.cpp
    ../../tools/marathon-app-runner/ipc/shellipcclients.cpp
    ../../shell/src/managers/settingsmanager.cpp
)
target_link_libraries(test_core_settingscontract Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_core_settingscontract PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
    ${CMAKE_SOURCE_DIR}/shell/src
)
target_compile_definitions(test_core_settingscontract PRIVATE MARATHON_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
add_test(NAME Core_SettingsContract COMMAND test_core_settingscontract)

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
endif()
