# Marathon Shell Component Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core Gui Qml Sql)

# Router tests (pure state machine, zero deps)
add_executable(test_shell_router
    test_router.cpp
    ../../shell/src/services/router.cpp
)
target_link_libraries(test_shell_router Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_router PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Shell_Router COMMAND test_shell_router)

# SessionStore: the PIN grace period after locking
add_executable(test_shell_sessionstore
    test_sessionstore.cpp
    ../../shell/src/services/sessionstore.cpp
)
target_link_libraries(test_shell_sessionstore Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_sessionstore PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_SessionStore COMMAND test_shell_sessionstore)

# AppModel tests (data model with validation)
add_executable(test_shell_appmodel
    test_appmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_appmodel Qt6::Test Qt6::Core)
target_include_directories(test_shell_appmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Shell_AppModel COMMAND test_shell_appmodel)

# NotificationModel tests (data model, add/dismiss/read)
add_executable(test_shell_notificationmodel
    test_notificationmodel.cpp
    ../../shell/src/models/notificationmodel.cpp
    ../../shell/src/dbus/notificationdatabase.cpp
)
target_link_libraries(test_shell_notificationmodel Qt6::Test Qt6::Core Qt6::Sql Qt6::Qml)
target_include_directories(test_shell_notificationmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Shell_NotificationModel COMMAND test_shell_notificationmodel)

# TaskModel tests (data model, launch/close/update)
add_executable(test_shell_taskmodel
    test_taskmodel.cpp
    ../../shell/src/models/taskmodel.cpp
)
target_link_libraries(test_shell_taskmodel Qt6::Test Qt6::Core Qt6::Gui Qt6::Qml)
target_include_directories(test_shell_taskmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
)
add_test(NAME Shell_TaskModel COMMAND test_shell_taskmodel)

# Ambience derivation from the wallpaper
add_executable(test_shell_ambiencederivation
    test_ambiencederivation.cpp
    ../../shell/src/services/ambiencederivation.cpp
)
target_link_libraries(test_shell_ambiencederivation Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_ambiencederivation PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Shell_AmbienceDerivation COMMAND test_shell_ambiencederivation)

# Ambience service: wallpaper seed and debounced publishing
add_executable(test_shell_ambienceservice
    test_ambienceservice.cpp
    ../../shell/src/services/ambienceservice.cpp
    ../../shell/src/services/ambiencederivation.cpp
)
target_link_libraries(test_shell_ambienceservice Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_ambienceservice PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Shell_AmbienceService COMMAND test_shell_ambienceservice)

# Which keys the compositor keeps for system navigation
add_executable(test_shell_keyrouting test_keyrouting.cpp)
target_link_libraries(test_shell_keyrouting Qt6::Test Qt6::Core)
target_include_directories(test_shell_keyrouting PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_KeyRouting COMMAND test_shell_keyrouting)

# Nemo.Ngf events to vibration patterns
add_executable(test_shell_ngfevents test_ngfevents.cpp)
target_link_libraries(test_shell_ngfevents Qt6::Test Qt6::Core)
target_include_directories(test_shell_ngfevents PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_NgfEvents COMMAND test_shell_ngfevents)

# Nemo.Ngf backend (com.nokia.NonGraphicFeedback1)
add_executable(test_shell_ngfservice test_ngfservice.cpp ../../shell/src/services/ngfservice.cpp)
target_link_libraries(test_shell_ngfservice Qt6::Test Qt6::Core)
target_include_directories(test_shell_ngfservice PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_NgfService COMMAND test_shell_ngfservice)

# Nemo.Notifications remote actions (x-nemo-remote-action-*)
find_package(Qt6 REQUIRED COMPONENTS DBus)
add_executable(test_shell_nemoremoteaction test_nemoremoteaction.cpp)
target_link_libraries(test_shell_nemoremoteaction Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_shell_nemoremoteaction PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/dbus)
add_test(NAME Shell_NemoRemoteAction COMMAND test_shell_nemoremoteaction)

# Keel cover windows (keel/shell/PROTOCOL.md section 3)
add_executable(test_shell_keelcover test_keelcover.cpp)
target_link_libraries(test_shell_keelcover Qt6::Test Qt6::Core)
target_include_directories(test_shell_keelcover PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_KeelCover COMMAND test_shell_keelcover)

# xdg-desktop-portal Settings backend (appearance from the ambience)
find_package(Qt6 REQUIRED COMPONENTS Gui DBus)
add_executable(test_shell_portalsettings test_portalsettings.cpp ../../shell/src/dbus/portalsettings.cpp)
target_link_libraries(test_shell_portalsettings Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus)
target_include_directories(test_shell_portalsettings PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/dbus)
add_test(NAME Shell_PortalSettings COMMAND test_shell_portalsettings)

# Sailfish apps launch under marathon-keel-host
add_executable(test_shell_sailfishlaunch test_sailfishlaunch.cpp)
target_link_libraries(test_shell_sailfishlaunch Qt6::Test Qt6::Core)
target_include_directories(test_shell_sailfishlaunch PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_SailfishLaunch COMMAND test_shell_sailfishlaunch)

# Status bar glyphs: real Phosphor names, state carried by the glyph
add_executable(test_shell_statusbaricons test_statusbaricons.cpp ../../shell/src/services/statusbariconservicecpp.cpp)
target_link_libraries(test_shell_statusbaricons Qt6::Test Qt6::Core)
target_include_directories(test_shell_statusbaricons PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
target_compile_definitions(test_shell_statusbaricons PRIVATE GLYPHS_JS="${CMAKE_SOURCE_DIR}/shell/qml/ui/PhosphorGlyphs.js")
add_test(NAME Shell_StatusBarIcons COMMAND test_shell_statusbaricons)

# org.freedesktop.Notifications Notify: actions and reply hints reach the banner map
add_executable(test_shell_freedesktopnotify
    test_freedesktopnotify.cpp
    ../../shell/src/dbus/freedesktopnotifications.cpp
    ../../shell/src/dbus/notificationdatabase.cpp
    ../../shell/src/models/notificationmodel.cpp
)
target_link_libraries(test_shell_freedesktopnotify Qt6::Test Qt6::Core Qt6::Sql Qt6::Qml Qt6::DBus)
target_include_directories(test_shell_freedesktopnotify PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/dbus
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/shell/src/managers
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Shell_FreedesktopNotify COMMAND test_shell_freedesktopnotify)

# AlarmManager: one-shot, hidden, exactly-timed alarms (countdown timers)
find_package(Qt6 REQUIRED COMPONENTS Multimedia)
add_executable(test_shell_alarmmanager
    test_alarmmanager.cpp
    ../../shell/src/managers/alarmmanagercpp.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/powermanagercpp.cpp
    ../../shell/src/managers/hapticmanager.cpp
)
target_link_libraries(test_shell_alarmmanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml Qt6::Multimedia)
target_include_directories(test_shell_alarmmanager PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_AlarmManager COMMAND test_shell_alarmmanager)
set_tests_properties(Shell_AlarmManager PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
