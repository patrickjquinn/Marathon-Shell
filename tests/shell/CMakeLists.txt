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

# SinkVolume: volume and mute follow the current default sink
add_executable(test_shell_sinkvolume
    test_sinkvolume.cpp
    ../../shell/src/managers/sinkvolume.cpp
)
target_link_libraries(test_shell_sinkvolume Qt6::Test Qt6::Core)
target_include_directories(test_shell_sinkvolume PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers)
add_test(NAME Shell_SinkVolume COMMAND test_shell_sinkvolume)

# MPRIS2Controller against fake players on a private session bus
find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    find_package(Qt6 REQUIRED COMPONENTS DBus)
    add_executable(test_shell_mpris2controller
        test_mpris2controller.cpp
        ../../shell/src/managers/mpris2controller.cpp
    )
    target_link_libraries(test_shell_mpris2controller Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
    target_include_directories(test_shell_mpris2controller PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers)
    add_test(NAME Shell_MPRIS2Controller COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_mpris2controller>)
endif()

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

# System back for native apps: the key per toolkit, and what counts as handled
add_executable(test_shell_nativeback test_nativeback.cpp)
target_link_libraries(test_shell_nativeback Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_nativeback PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_NativeBack COMMAND test_shell_nativeback)

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
add_executable(test_shell_portalsettings test_portalsettings.cpp ../../shell/src/dbus/portalsettings.cpp
    ../../shell/src/services/toolkittheme.cpp)
target_link_libraries(test_shell_portalsettings Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus)
target_include_directories(test_shell_portalsettings PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/dbus)
add_test(NAME Shell_PortalSettings COMMAND test_shell_portalsettings)

# GTK / libadwaita / KDE colours derived from the ambience
add_executable(test_shell_toolkittheme test_toolkittheme.cpp ../../shell/src/services/toolkittheme.cpp)
target_link_libraries(test_shell_toolkittheme Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_toolkittheme PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
target_compile_definitions(test_shell_toolkittheme PRIVATE
    MARATHON_TOOLKIT_THEMES="${CMAKE_SOURCE_DIR}/shell/toolkit-themes")
add_test(NAME Shell_ToolkitTheme COMMAND test_shell_toolkittheme)

add_executable(test_shell_toolkitthemewriter test_toolkitthemewriter.cpp
    ../../shell/src/services/toolkitthemewriter.cpp ../../shell/src/services/toolkittheme.cpp)
target_link_libraries(test_shell_toolkitthemewriter Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_toolkitthemewriter PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_ToolkitThemeWriter COMMAND test_shell_toolkitthemewriter)

# Sailfish apps launch under marathon-keel-host
add_executable(test_shell_sailfishlaunch test_sailfishlaunch.cpp)
target_link_libraries(test_shell_sailfishlaunch Qt6::Test Qt6::Core)
target_include_directories(test_shell_sailfishlaunch PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_SailfishLaunch COMMAND test_shell_sailfishlaunch)

add_executable(test_shell_processtree test_processtree.cpp)
target_link_libraries(test_shell_processtree Qt6::Test Qt6::Core)
target_include_directories(test_shell_processtree PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_ProcessTree COMMAND test_shell_processtree)

add_executable(test_shell_processstopper test_processstopper.cpp ../../shell/src/services/processstopper.cpp)
target_link_libraries(test_shell_processstopper Qt6::Test Qt6::Core)
target_include_directories(test_shell_processstopper PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_ProcessStopper COMMAND test_shell_processstopper)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBDRM REQUIRED libdrm)
add_executable(test_shell_drmmasterwait test_drmmasterwait.cpp ../../shell/src/managers/drmmasterwait.cpp)
target_link_libraries(test_shell_drmmasterwait Qt6::Test Qt6::Core ${LIBDRM_LIBRARIES})
target_include_directories(test_shell_drmmasterwait PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${LIBDRM_INCLUDE_DIRS})
add_test(NAME Shell_DrmMasterWait COMMAND test_shell_drmmasterwait)

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
    ../../shell/src/services/notificationtarget.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_freedesktopnotify Qt6::Test Qt6::Core Qt6::Sql Qt6::Qml Qt6::DBus)
target_include_directories(test_shell_freedesktopnotify PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src/services
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
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/managers/powermanagercpp.cpp
    ../../shell/src/managers/hapticmanager.cpp
)
target_link_libraries(test_shell_alarmmanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml Qt6::Multimedia)
target_include_directories(test_shell_alarmmanager PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_AlarmManager COMMAND test_shell_alarmmanager)
set_tests_properties(Shell_AlarmManager PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# A resume at the time marathon-background armed is a background wake
add_executable(test_shell_backgroundwake
    test_backgroundwake.cpp
    ../../shell/src/managers/powermanagercpp.cpp
)
target_link_libraries(test_shell_backgroundwake Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
target_include_directories(test_shell_backgroundwake PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_BackgroundWake COMMAND test_shell_backgroundwake)

# SecurityManager: quick PIN failures count towards the lockout
find_package(Qt6 REQUIRED COMPONENTS Concurrent)
add_executable(test_shell_securitymanager
    test_securitymanager.cpp
    ../../shell/src/managers/securitymanager.cpp
)
target_link_libraries(test_shell_securitymanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml Qt6::Concurrent ${PAM_LIBRARY})
target_include_directories(test_shell_securitymanager PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${CMAKE_SOURCE_DIR}/shell/src/components ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_SecurityManager COMMAND test_shell_securitymanager)

# A background launch starts the app without bringing it to the front
add_executable(test_shell_backgroundlaunch
    test_backgroundlaunch.cpp
    ../../shell/src/services/applaunchservice.cpp
    ../../shell/src/services/applifecyclemanager.cpp
    ../../shell/src/services/cgroupmanager.cpp
    ../../shell/src/services/processstopper.cpp
    ../../shell/src/models/taskmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/managers/screenmetrics.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_backgroundlaunch Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
target_include_directories(test_shell_backgroundlaunch PRIVATE
    ${CMAKE_SOURCE_DIR}/shell
    ${CMAKE_SOURCE_DIR}/shell/src/services
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Shell_BackgroundLaunch COMMAND test_shell_backgroundlaunch)

# A Keel Actions app gives up its bus name before it is frozen, and is woken
if(DBUS_RUN_SESSION)
    add_executable(test_shell_keelactionsfreeze
        test_keelactionsfreeze.cpp
        ../../shell/src/services/applaunchservice.cpp
        ../../shell/src/services/applifecyclemanager.cpp
        ../../shell/src/services/cgroupmanager.cpp
        ../../shell/src/services/processstopper.cpp
        ../../shell/src/models/taskmodel.cpp
        ../../shell/src/models/appmodel.cpp
        ../../shell/src/managers/deviceprofile.cpp
        ../../shell/src/managers/screenmetrics.cpp
        ../../marathon-core/src/marathonappregistry.cpp
    )
    target_link_libraries(test_shell_keelactionsfreeze Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
    target_include_directories(test_shell_keelactionsfreeze PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src/services
        ${CMAKE_SOURCE_DIR}/shell/src/models
        ${CMAKE_SOURCE_DIR}/marathon-core/src
    )
    add_test(NAME Shell_KeelActionsFreeze
        COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_keelactionsfreeze>)
endif()

# Native apps in their own systemd scope are frozen through the user manager
add_executable(test_shell_appscope test_appscope.cpp)
target_link_libraries(test_shell_appscope Qt6::Test Qt6::Core)
target_include_directories(test_shell_appscope PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_AppScope COMMAND test_shell_appscope)

if(DBUS_RUN_SESSION)
    add_executable(test_shell_nativelifecycle
        test_nativelifecycle.cpp
        ../../shell/src/services/applaunchservice.cpp
        ../../shell/src/services/applifecyclemanager.cpp
        ../../shell/src/services/cgroupmanager.cpp
        ../../shell/src/services/processstopper.cpp
        ../../shell/src/models/taskmodel.cpp
        ../../shell/src/models/appmodel.cpp
        ../../shell/src/managers/deviceprofile.cpp
        ../../shell/src/managers/screenmetrics.cpp
        ../../marathon-core/src/marathonappregistry.cpp
    )
    target_link_libraries(test_shell_nativelifecycle Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
    target_include_directories(test_shell_nativelifecycle PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src/services
        ${CMAKE_SOURCE_DIR}/shell/src/models
        ${CMAKE_SOURCE_DIR}/marathon-core/src
    )
    add_test(NAME Shell_NativeLifecycle
        COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_nativelifecycle>)
endif()

# A call for a Keel app that is not running is bus-activated through the shell
find_program(BUSCTL busctl)
find_program(DBUS_DAEMON dbus-daemon)
if(BUSCTL AND DBUS_DAEMON)
    set(_services ${CMAKE_CURRENT_BINARY_DIR}/keel-activation-services)
    set(MARATHON_ACTIVATE ${CMAKE_SOURCE_DIR}/systemd/marathon-activate)
    foreach(KEEL_APP notes refused)
        configure_file(${CMAKE_SOURCE_DIR}/apps/keel-actions.service.in
            ${_services}/org.marathonos.${KEEL_APP}.service @ONLY)
    endforeach()
    add_executable(test_shell_keelactivation test_keelactivation.cpp)
    target_link_libraries(test_shell_keelactivation Qt6::Test Qt6::Core Qt6::DBus)
    target_compile_definitions(test_shell_keelactivation PRIVATE SERVICES_DIR="${_services}")
    add_test(NAME Shell_KeelActivation COMMAND test_shell_keelactivation)
endif()

# Gesture engine: velocity window, commit decisions, settle spring
add_executable(test_shell_gesturetracker
    test_gesturetracker.cpp
    ../../shell/src/services/gesturetracker.cpp
)
target_link_libraries(test_shell_gesturetracker Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_gesturetracker PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_GestureTracker COMMAND test_shell_gesturetracker)

# WindowTextureItem: rounded, cropped texture geometry and the corner shader
find_package(Qt6 REQUIRED COMPONENTS Quick)
add_executable(test_shell_windowtextureitem
    test_windowtextureitem.cpp
    ../../shell/src/components/windowtextureitem.cpp
)
qt_add_resources(test_shell_windowtextureitem "test_shell_shaders"
    PREFIX "/marathon/shaders"
    BASE "${CMAKE_SOURCE_DIR}/shell/shaders"
    FILES
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.vert.qsb
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.frag.qsb
)
target_link_libraries(test_shell_windowtextureitem Qt6::Test Qt6::Quick)
add_test(NAME Shell_WindowTextureItem COMMAND test_shell_windowtextureitem)
set_tests_properties(Shell_WindowTextureItem PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# WindowTextureItem under QtWayland's commit pattern: texture deleted, then
# textureChanged, inside the source's updatePaintNode. Null RHI: the batch
# renderer without a GPU.
add_executable(test_shell_windowtexturestress
    test_windowtexturestress.cpp
    ../../shell/src/components/windowtextureitem.cpp
)
qt_add_resources(test_shell_windowtexturestress "test_shell_stress_shaders"
    PREFIX "/marathon/shaders"
    BASE "${CMAKE_SOURCE_DIR}/shell/shaders"
    FILES
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.vert.qsb
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.frag.qsb
)
target_link_libraries(test_shell_windowtexturestress Qt6::Test Qt6::Quick)
add_test(NAME Shell_WindowTextureStress COMMAND test_shell_windowtexturestress)
set_tests_properties(Shell_WindowTextureStress PROPERTIES ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=rhi;QSG_RHI_BACKEND=null;QSG_RENDER_LOOP=basic")

# Frame callbacks of hidden surfaces: about once a second
add_executable(test_shell_hiddenframethrottle test_hiddenframethrottle.cpp)
target_link_libraries(test_shell_hiddenframethrottle Qt6::Test Qt6::Core)
add_test(NAME Shell_HiddenFrameThrottle COMMAND test_shell_hiddenframethrottle)

# NativeClientScale: the scale native apps get, and a client being told it
find_package(Qt6 COMPONENTS WaylandCompositor)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner)
if(TARGET Qt6::WaylandCompositor AND WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER)
    set(_fractional_xml ${CMAKE_SOURCE_DIR}/shell/protocols/fractional-scale-v1.xml)
    set(_fractional_gen ${CMAKE_CURRENT_BINARY_DIR}/fractional-scale)
    file(MAKE_DIRECTORY ${_fractional_gen})
    add_custom_command(
        OUTPUT ${_fractional_gen}/fractional-scale-v1-server.h
               ${_fractional_gen}/fractional-scale-v1-client.h
               ${_fractional_gen}/fractional-scale-v1.c
        COMMAND ${WAYLAND_SCANNER} server-header ${_fractional_xml} ${_fractional_gen}/fractional-scale-v1-server.h
        COMMAND ${WAYLAND_SCANNER} client-header ${_fractional_xml} ${_fractional_gen}/fractional-scale-v1-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${_fractional_xml} ${_fractional_gen}/fractional-scale-v1.c
        DEPENDS ${_fractional_xml})
    add_executable(test_shell_nativeclientscale
        test_nativeclientscale.cpp
        ../../shell/src/wayland/nativeclientscale.cpp
        ${_fractional_gen}/fractional-scale-v1-server.h
        ${_fractional_gen}/fractional-scale-v1-client.h
        ${_fractional_gen}/fractional-scale-v1.c
    )
    target_link_libraries(test_shell_nativeclientscale
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_nativeclientscale PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${_fractional_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_NativeClientScale COMMAND test_shell_nativeclientscale)
    set_tests_properties(Shell_NativeClientScale PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
