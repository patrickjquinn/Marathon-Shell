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

# ForegroundApp: the app in front, "" at home, in the switcher or locked
add_executable(test_shell_foregroundapp
    test_foregroundapp.cpp
    ../../shell/src/services/foregroundapp.cpp
    ../../shell/src/services/sessionstore.cpp
    ../../shell/src/services/uistore.cpp
)
target_link_libraries(test_shell_foregroundapp Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_foregroundapp PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_ForegroundApp COMMAND test_shell_foregroundapp)

# AudioPolicyController: which sounds the profile lets through
find_package(Qt6 REQUIRED COMPONENTS Multimedia)
add_executable(test_shell_audiopolicy
    test_audiopolicy.cpp
    ../../shell/src/controllers/audiopolicycontroller.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/models/notificationmodel.cpp
    ../../shell/src/dbus/notificationdatabase.cpp
    ../../shell/src/services/notificationservicecpp.cpp
)
target_link_libraries(test_shell_audiopolicy Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml Qt6::Multimedia Qt6::Sql)
target_include_directories(test_shell_audiopolicy PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src
    ${CMAKE_SOURCE_DIR}/shell/src/managers
    ${CMAKE_SOURCE_DIR}/shell/src/controllers
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
target_compile_definitions(test_shell_audiopolicy PRIVATE MARATHON_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
add_test(NAME Shell_AudioPolicy COMMAND sh ${CMAKE_SOURCE_DIR}/tests/shell/with-media-roles.sh
    $<TARGET_FILE:test_shell_audiopolicy>)
set_tests_properties(Shell_AudioPolicy PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Tapping a notification shows its app, the registry's or not
add_executable(test_shell_notificationhandler
    test_notificationhandler.cpp
    ../../shell/src/services/notificationhandlercpp.cpp
    ../../shell/src/services/navigationroutercpp.cpp
    ../../shell/src/services/notificationtarget.cpp
    ../../shell/src/controllers/audiopolicycontroller.cpp
    ../../shell/src/managers/settingsmanager.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/models/notificationmodel.cpp
    ../../shell/src/dbus/notificationdatabase.cpp
    ../../shell/src/services/notificationservicecpp.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_notificationhandler Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml
    Qt6::Multimedia Qt6::Sql)
target_include_directories(test_shell_notificationhandler PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src
    ${CMAKE_SOURCE_DIR}/shell/src/managers
    ${CMAKE_SOURCE_DIR}/shell/src/controllers
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/shell/src/services
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Shell_NotificationHandler COMMAND test_shell_notificationhandler)

find_program(DBUS_RUN_SESSION dbus-run-session)

# AppModel tests (data model with validation)
add_executable(test_shell_appmodel
    test_appmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../shell/src/services/appstore.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_appmodel Qt6::Test Qt6::Core Qt6::Qml)
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

# The file chooser's list: folders, filters, search, recent
add_executable(test_shell_filechoosermodel test_filechoosermodel.cpp
    ../../shell/src/models/filechoosermodel.cpp)
target_link_libraries(test_shell_filechoosermodel Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_filechoosermodel PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/models)
add_test(NAME Shell_FileChooserModel COMMAND test_shell_filechoosermodel)

# xdg-desktop-portal FileChooser backend: requests, replies, Close, on a private bus
add_executable(test_shell_portalfilechooser test_portalfilechooser.cpp
    ../../shell/src/dbus/portalfilechooser.cpp)
target_link_libraries(test_shell_portalfilechooser Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_shell_portalfilechooser PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/dbus)
add_test(NAME Shell_PortalFileChooser
    COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_portalfilechooser>)

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
    ../../shell/src/models/appmodel.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_freedesktopnotify Qt6::Test Qt6::Core Qt6::Gui Qt6::Sql Qt6::Qml Qt6::DBus)
target_include_directories(test_shell_freedesktopnotify PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
    ${CMAKE_SOURCE_DIR}/shell/src/services
    ${CMAKE_SOURCE_DIR}/shell/src/dbus
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/shell/src/managers
    ${CMAKE_SOURCE_DIR}/shell/src
)
if(DBUS_RUN_SESSION)
    add_test(NAME Shell_FreedesktopNotify COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_freedesktopnotify>)
else()
    add_test(NAME Shell_FreedesktopNotify COMMAND test_shell_freedesktopnotify)
endif()


# SecurityManager: quick PIN failures count towards the lockout
find_package(Qt6 REQUIRED COMPONENTS Concurrent)
add_executable(test_shell_securitymanager
    test_securitymanager.cpp
)
target_link_libraries(test_shell_securitymanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml Qt6::Concurrent ${PAM_LIBRARY})
target_include_directories(test_shell_securitymanager PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${CMAKE_SOURCE_DIR}/shell/src/components ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_SecurityManager COMMAND test_shell_securitymanager)

# A background launch starts the app without bringing it to the front
add_executable(test_shell_backgroundlaunch
    test_backgroundlaunch.cpp
    ../../shell/src/services/applaunchservice.cpp
    ../../shell/src/services/applifecyclemanager.cpp
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

# One client's toplevels are separate apps, launched by another process
add_executable(test_shell_sharedclient
    test_sharedclient.cpp
    ../../shell/src/services/applaunchservice.cpp
    ../../shell/src/services/applifecyclemanager.cpp
    ../../shell/src/services/processstopper.cpp
    ../../shell/src/models/taskmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/managers/screenmetrics.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_sharedclient Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
target_include_directories(test_shell_sharedclient PRIVATE
    ${CMAKE_SOURCE_DIR}/shell
    ${CMAKE_SOURCE_DIR}/shell/src/services
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
# A private bus: an Android launch asks the session's systemd for Waydroid.
if(DBUS_RUN_SESSION)
    add_test(NAME Shell_SharedClient COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_sharedclient>)
else()
    add_test(NAME Shell_SharedClient COMMAND test_shell_sharedclient)
endif()

# The bwrap sandbox a Marathon app is launched in
add_executable(test_shell_sandboxlaunch
    test_sandboxlaunch.cpp
    ../../shell/src/services/applaunchservice.cpp
    ../../shell/src/services/applifecyclemanager.cpp
    ../../shell/src/services/processstopper.cpp
    ../../shell/src/models/taskmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/managers/screenmetrics.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_sandboxlaunch Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
target_include_directories(test_shell_sandboxlaunch PRIVATE
    ${CMAKE_SOURCE_DIR}/shell
    ${CMAKE_SOURCE_DIR}/shell/src/services
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Shell_SandboxLaunch COMMAND test_shell_sandboxlaunch)
set_tests_properties(Shell_SandboxLaunch PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The warm spare runners and which apps each may become
add_executable(test_shell_runnerpool
    test_runnerpool.cpp
    ../../shell/src/services/applaunchservice.cpp
    ../../shell/src/services/applifecyclemanager.cpp
    ../../shell/src/services/processstopper.cpp
    ../../shell/src/models/taskmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../shell/src/managers/deviceprofile.cpp
    ../../shell/src/managers/screenmetrics.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_runnerpool Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
target_include_directories(test_shell_runnerpool PRIVATE
    ${CMAKE_SOURCE_DIR}/shell
    ${CMAKE_SOURCE_DIR}/shell/src/services
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Shell_RunnerPool COMMAND test_shell_runnerpool)
set_tests_properties(Shell_RunnerPool PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# A Keel Actions app gives up its bus name before it is frozen, and is woken
if(DBUS_RUN_SESSION)
    add_executable(test_shell_keelactionsfreeze
        test_keelactionsfreeze.cpp
        ../../shell/src/services/applaunchservice.cpp
        ../../shell/src/services/applifecyclemanager.cpp
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

# The shell leaves Waydroid's container running; Android freezes its own apps
if(DBUS_RUN_SESSION)
    add_executable(test_shell_androidfreeze
        test_androidfreeze.cpp
        ../../shell/src/services/applaunchservice.cpp
        ../../shell/src/services/applifecyclemanager.cpp
        ../../shell/src/services/processstopper.cpp
        ../../shell/src/models/taskmodel.cpp
        ../../shell/src/models/appmodel.cpp
        ../../shell/src/managers/deviceprofile.cpp
        ../../shell/src/managers/screenmetrics.cpp
        ../../marathon-core/src/marathonappregistry.cpp
    )
    target_link_libraries(test_shell_androidfreeze Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
    target_include_directories(test_shell_androidfreeze PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src/services
        ${CMAKE_SOURCE_DIR}/shell/src/models
        ${CMAKE_SOURCE_DIR}/marathon-core/src
    )
    add_test(NAME Shell_AndroidFreeze
        COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_androidfreeze>)
endif()

if(DBUS_RUN_SESSION)
    add_executable(test_shell_nativelifecycle
        test_nativelifecycle.cpp
        ../../shell/src/services/applaunchservice.cpp
        ../../shell/src/services/applifecyclemanager.cpp
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

# app.show for an app that is not running, through the real runner (registered
# in tests/CMakeLists.txt, which finds Keel's Silica)
if(DBUS_DAEMON)
    add_executable(test_shell_keelshow test_keelshow.cpp)
    target_link_libraries(test_shell_keelshow Qt6::Test Qt6::Core Qt6::DBus)
endif()

# The shell's own Keel Actions on a private bus: dispatch, arguments, who may call
if(DBUS_RUN_SESSION AND BUSCTL)
    add_executable(test_shell_shellkeelactions
        test_shellkeelactions.cpp
        ../../shell/src/ipc/shellkeelactions.cpp
        ../../shell/src/services/uistore.cpp
        ../../shell/src/services/sessionstore.cpp
        ../../shell/src/managers/settingsmanager.cpp
        ../../shell/src/managers/deviceprofile.cpp
        ../../shell/src/managers/screenmetrics.cpp
        ../../shell/src/services/applaunchservice.cpp
        ../../shell/src/services/applifecyclemanager.cpp
        ../../shell/src/services/processstopper.cpp
        ../../shell/src/models/taskmodel.cpp
        ../../shell/src/models/appmodel.cpp
        ../../marathon-core/src/marathonappregistry.cpp
    )
    qt_add_resources(test_shell_shellkeelactions "keel_actions"
        PREFIX "/keel"
        BASE "${CMAKE_SOURCE_DIR}/shell/dbus"
        FILES ${CMAKE_SOURCE_DIR}/shell/dbus/keel-actions.json
    )
    target_link_libraries(test_shell_shellkeelactions Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus
        Qt6::Qml)
    target_include_directories(test_shell_shellkeelactions PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src
        ${CMAKE_SOURCE_DIR}/shell/src/managers
        ${CMAKE_SOURCE_DIR}/shell/src/controllers
        ${CMAKE_SOURCE_DIR}/shell/src/services
        ${CMAKE_SOURCE_DIR}/shell/src/models
        ${CMAKE_SOURCE_DIR}/marathon-core/src
    )
    add_test(NAME Shell_ShellKeelActions
        COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_shellkeelactions>)

    # The share sheet's org.sailfishos.share, against fake receivers on a private bus
    add_executable(test_shell_shareservice
        test_shareservice.cpp
        ../../shell/src/services/shareservice.cpp
        ../../tools/marathon-app-runner/ipc/dbusnormalize.cpp
        ../../marathon-core/src/marathonappregistry.cpp
    )
    target_link_libraries(test_shell_shareservice Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus)
    target_include_directories(test_shell_shareservice PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/services
        ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner/ipc
        ${CMAKE_SOURCE_DIR}/marathon-core/src
    )
    add_test(NAME Shell_ShareService
        COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_shell_shareservice>)
    set_tests_properties(Shell_ShareService PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
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

# Touch moves resampled to one a frame
add_executable(test_shell_touchresampler test_touchresampler.cpp
    ../../shell/src/services/touchresampler.cpp)
set_target_properties(test_shell_touchresampler PROPERTIES AUTOMOC ON)
target_link_libraries(test_shell_touchresampler Qt6::Test Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::Qml)
target_include_directories(test_shell_touchresampler PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_TouchResampler COMMAND test_shell_touchresampler)

# The touch CPU boost's resting floor
add_executable(test_shell_inputboost test_inputboost.cpp ../../shell/src/services/inputboost.cpp)
set_target_properties(test_shell_inputboost PROPERTIES AUTOMOC ON)
target_link_libraries(test_shell_inputboost Qt6::Test Qt6::Core)
target_include_directories(test_shell_inputboost PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_InputBoost COMMAND test_shell_inputboost)

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

    # security-context-v1: sandboxed clients are tagged and miss privileged globals
    set(_security_xml ${CMAKE_SOURCE_DIR}/shell/protocols/security-context-v1.xml)
    set(_security_gen ${CMAKE_CURRENT_BINARY_DIR}/security-context)
    file(MAKE_DIRECTORY ${_security_gen})
    add_custom_command(
        OUTPUT ${_security_gen}/security-context-v1-server.h
               ${_security_gen}/security-context-v1-client.h
               ${_security_gen}/security-context-v1.c
        COMMAND ${WAYLAND_SCANNER} server-header ${_security_xml} ${_security_gen}/security-context-v1-server.h
        COMMAND ${WAYLAND_SCANNER} client-header ${_security_xml} ${_security_gen}/security-context-v1-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${_security_xml} ${_security_gen}/security-context-v1.c
        DEPENDS ${_security_xml})
    add_executable(test_shell_securitycontext
        test_securitycontext.cpp
        ../../shell/src/wayland/securitycontextv1.cpp
        ${_security_gen}/security-context-v1-server.h
        ${_security_gen}/security-context-v1-client.h
        ${_security_gen}/security-context-v1.c
    )
    target_link_libraries(test_shell_securitycontext
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_securitycontext PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${_security_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_SecurityContext COMMAND test_shell_securitycontext)
    set_tests_properties(Shell_SecurityContext PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # A toplevel is sent a configure only when its size or states change
    pkg_get_variable(_protocols_dir wayland-protocols pkgdatadir)
    set(_xdg_shell_xml ${_protocols_dir}/stable/xdg-shell/xdg-shell.xml)
    find_package(Qt6 COMPONENTS WaylandCompositorPrivate QUIET)
    if(EXISTS ${_xdg_shell_xml} AND TARGET Qt6::WaylandCompositorPrivate)
        set(_xdg_shell_gen ${CMAKE_CURRENT_BINARY_DIR}/xdg-shell)
        file(MAKE_DIRECTORY ${_xdg_shell_gen})
        add_custom_command(
            OUTPUT ${_xdg_shell_gen}/xdg-shell-client.h ${_xdg_shell_gen}/xdg-shell.c
            COMMAND ${WAYLAND_SCANNER} client-header ${_xdg_shell_xml} ${_xdg_shell_gen}/xdg-shell-client.h
            COMMAND ${WAYLAND_SCANNER} private-code ${_xdg_shell_xml} ${_xdg_shell_gen}/xdg-shell.c
            DEPENDS ${_xdg_shell_xml})
        add_executable(test_shell_toplevelconfigure
            test_toplevelconfigure.cpp
            ../../shell/src/wayland/toplevelconfigure.cpp
            ${_xdg_shell_gen}/xdg-shell-client.h
            ${_xdg_shell_gen}/xdg-shell.c
        )
        target_compile_definitions(test_shell_toplevelconfigure PRIVATE HAVE_WAYLAND_PRIVATE)
        target_link_libraries(test_shell_toplevelconfigure
            Qt6::Test Qt6::Gui Qt6::WaylandCompositor Qt6::WaylandCompositorPrivate
            ${WAYLAND_CLIENT_LIBRARIES})
        target_include_directories(test_shell_toplevelconfigure PRIVATE
            ${CMAKE_SOURCE_DIR}/shell/src/wayland ${_xdg_shell_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
        add_test(NAME Shell_ToplevelConfigure COMMAND test_shell_toplevelconfigure)
        set_tests_properties(Shell_ToplevelConfigure PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    endif()

    # Server and client headers plus marshalling code for a protocol XML,
    # appended to the list named by OUT.
    function(marathon_test_protocol XML STEM OUT)
        set(_gen ${CMAKE_CURRENT_BINARY_DIR}/protocols)
        file(MAKE_DIRECTORY ${_gen})
        add_custom_command(
            OUTPUT ${_gen}/${STEM}-server.h ${_gen}/${STEM}-client.h ${_gen}/${STEM}.c
            COMMAND ${WAYLAND_SCANNER} server-header ${XML} ${_gen}/${STEM}-server.h
            COMMAND ${WAYLAND_SCANNER} client-header ${XML} ${_gen}/${STEM}-client.h
            COMMAND ${WAYLAND_SCANNER} private-code ${XML} ${_gen}/${STEM}.c
            DEPENDS ${XML})
        set(${OUT} ${${OUT}} ${_gen}/${STEM}-server.h ${_gen}/${STEM}-client.h ${_gen}/${STEM}.c
            PARENT_SCOPE)
    endfunction()

    # xdg-activation-v1: launch tokens, and the focus rule for client tokens
    set(_activation_protocol)
    marathon_test_protocol(${CMAKE_SOURCE_DIR}/shell/protocols/xdg-activation-v1.xml
        xdg-activation-v1 _activation_protocol)
    add_executable(test_shell_xdgactivation
        test_xdgactivation.cpp
        ../../shell/src/wayland/xdgactivationv1.cpp
        ${_activation_protocol}
    )
    target_link_libraries(test_shell_xdgactivation
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_xdgactivation PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${CMAKE_CURRENT_BINARY_DIR}/protocols
        ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_XdgActivation COMMAND test_shell_xdgactivation)
    set_tests_properties(Shell_XdgActivation PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    add_executable(test_shell_foreignfocus test_foreignfocus.cpp)
    target_link_libraries(test_shell_foreignfocus
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_foreignfocus PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_ForeignFocus COMMAND test_shell_foreignfocus)
    set_tests_properties(Shell_ForeignFocus PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # marathon-surface-v1: bind policy, window flags, insets, back events
    set(_marathon_surface_protocol)
    marathon_test_protocol(${CMAKE_SOURCE_DIR}/shell/protocols/marathon-surface-v1.xml
        marathon-surface-v1 _marathon_surface_protocol)
    marathon_test_protocol(${CMAKE_SOURCE_DIR}/shell/protocols/xdg-shell.xml
        xdg-shell _marathon_surface_protocol)
    add_executable(test_shell_marathonsurface
        test_marathonsurface.cpp
        ../../shell/src/wayland/marathonsurfacev1.cpp
        ../../shell/src/wayland/securitycontextv1.cpp
        ${_marathon_surface_protocol}
        ${_security_gen}/security-context-v1-server.h
        ${_security_gen}/security-context-v1.c
    )
    target_link_libraries(test_shell_marathonsurface
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_marathonsurface PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${CMAKE_CURRENT_BINARY_DIR}/protocols
        ${_security_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_MarathonSurface COMMAND test_shell_marathonsurface)
    set_tests_properties(Shell_MarathonSurface PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # Marathon's keyboard against a Waydroid-like window: hints and commits
    # reach RemoteTextInput with Qt focus or only the seat's keyboard focus
    add_executable(test_shell_remotetextinputwayland
        test_remotetextinputwayland.cpp
        ../../shell/src/services/remotetextinput.cpp
        ../../shell/src/services/inputcontext.cpp
        ../../shell/src/managers/marathoninputmethodengine.cpp
        ../../shell/src/wayland/remotetextinputtarget.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/protocols/xdg-shell-client.h
        ${CMAKE_CURRENT_BINARY_DIR}/protocols/xdg-shell.c
    )
    target_link_libraries(test_shell_remotetextinputwayland
        Qt6::Test Qt6::Quick Qt6::DBus Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_remotetextinputwayland PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src ${CMAKE_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/protocols
        ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_RemoteTextInputWayland COMMAND test_shell_remotetextinputwayland)
    set_tests_properties(Shell_RemoteTextInputWayland PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()

# The keyboard's replacements reach a text-input-v3 client as byte deletions
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
set(_text_input_xml ${WAYLAND_PROTOCOLS_DIR}/unstable/text-input/text-input-unstable-v3.xml)
if(TARGET Qt6::WaylandCompositor AND WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER AND EXISTS ${_text_input_xml})
    set(_text_input_gen ${CMAKE_CURRENT_BINARY_DIR}/text-input)
    file(MAKE_DIRECTORY ${_text_input_gen})
    add_custom_command(
        OUTPUT ${_text_input_gen}/text-input-unstable-v3-client.h
               ${_text_input_gen}/text-input-unstable-v3.c
        COMMAND ${WAYLAND_SCANNER} client-header ${_text_input_xml} ${_text_input_gen}/text-input-unstable-v3-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${_text_input_xml} ${_text_input_gen}/text-input-unstable-v3.c
        DEPENDS ${_text_input_xml})
    add_executable(test_shell_textinputreplace
        test_textinputreplace.cpp
        ../../shell/src/services/inputcontext.cpp
        ${_text_input_gen}/text-input-unstable-v3-client.h
        ${_text_input_gen}/text-input-unstable-v3.c
    )
    target_link_libraries(test_shell_textinputreplace
        Qt6::Test Qt6::Quick Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_textinputreplace PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src ${_text_input_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_TextInputReplace COMMAND test_shell_textinputreplace)
    set_tests_properties(Shell_TextInputReplace PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()

# Marathon's keyboard types into an input method service's editors (Deckard's
# Android apps): queries, commits and keys for the window it reported
add_executable(test_shell_remotetextinput
    test_remotetextinput.cpp
    ../../shell/src/services/remotetextinput.cpp
    ../../shell/src/services/inputcontext.cpp
)
target_link_libraries(test_shell_remotetextinput Qt6::Test Qt6::Quick Qt6::DBus)
target_include_directories(test_shell_remotetextinput PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_RemoteTextInput COMMAND test_shell_remotetextinput)
set_tests_properties(Shell_RemoteTextInput PROPERTIES ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")

# One screen state, blanked and woken through the backlight, and touch works
# again after a blank and wake
find_package(Qt6 REQUIRED COMPONENTS Quick)
add_executable(test_shell_screenstate test_screenstate.cpp
    ../../shell/src/services/waketouchfilter.cpp)
target_link_libraries(test_shell_screenstate Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml
    Qt6::Quick)
target_include_directories(test_shell_screenstate PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_ScreenState COMMAND test_shell_screenstate)
set_tests_properties(Shell_ScreenState PROPERTIES ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")

# Power against fake logind, power profiles and systemd: locks, profiles, wake-ups
add_executable(test_shell_powermanager test_powermanager.cpp)
target_link_libraries(test_shell_powermanager Qt6::Test Qt6::Core Qt6::DBus)
add_test(NAME Shell_PowerManager COMMAND test_shell_powermanager)

# Brightness lands on hardware levels; auto-brightness only with a light sensor
add_executable(test_shell_brightness test_brightness.cpp)
target_link_libraries(test_shell_brightness Qt6::Test Qt6::Core)
add_test(NAME Shell_Brightness COMMAND test_shell_brightness)

# The shell's Rust half (crates/marathon-shell-native) backs classes most
# of these tests compile; every shell test links it.
get_property(_shell_tests DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
foreach(_t IN LISTS _shell_tests)
    get_target_property(_type ${_t} TYPE)
    if(_t MATCHES "^test_shell_" AND _type STREQUAL "EXECUTABLE")
        target_link_libraries(${_t} marathon_shell_native)
    endif()
endforeach()
