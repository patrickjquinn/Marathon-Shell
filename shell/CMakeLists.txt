set(SOURCES
    main.cpp
    src/desktopfileparser.h
    src/desktopfileparser.cpp
    src/appmodel.h
    src/appmodel.cpp
    src/taskmodel.h
    src/taskmodel.cpp
    src/notificationmodel.h
    src/notificationmodel.cpp
    src/crashhandler.h
    src/crashhandler.cpp
    src/marathonappprocess.h
    src/marathonappprocess.cpp
    qml/keyboard/Data/WordEngine.h
    qml/keyboard/Data/WordEngine.cpp
    src/networkmanagercpp.h
    src/networkmanagercpp.cpp
    src/powermanagercpp.h
    src/powermanagercpp.cpp
    src/displaymanagercpp.h
    src/displaymanagercpp.cpp
    src/audiomanagercpp.h
    src/audiomanagercpp.cpp
    src/modemmanagercpp.h
    src/modemmanagercpp.cpp
    src/sensormanagercpp.h
    src/sensormanagercpp.cpp
    src/settingsmanager.h
    src/settingsmanager.cpp
    src/platformcpp.h
    src/storagemanager.h
    src/storagemanager.cpp
    src/bluetoothmanager.h
    src/bluetoothmanager.cpp
    src/bluetoothagent.h
    src/bluetoothagent.cpp
    src/marathoninputmethodengine.h
    src/marathoninputmethodengine.cpp
    src/marathonapploader.h
    src/marathonapploader.cpp
    src/marathoninputmethodengine.h
    src/marathoninputmethodengine.cpp
    src/storagemanager.h
    src/storagemanager.cpp
    src/rtscheduler.h
    src/rtscheduler.cpp
    src/dbus/marathonapplicationservice.h
    src/dbus/marathonapplicationservice.cpp
    src/dbus/marathonsystemservice.h
    src/dbus/marathonsystemservice.cpp
    src/dbus/marathonnotificationservice.h
    src/dbus/marathonnotificationservice.cpp
    src/dbus/freedesktopnotifications.h
    src/dbus/freedesktopnotifications.cpp
    src/dbus/notificationdatabase.h
    src/dbus/notificationdatabase.cpp
    src/dbus/marathonstorageservice.h
    src/dbus/marathonstorageservice.cpp
    src/dbus/marathonsettingsservice.h
    src/dbus/marathonsettingsservice.cpp
    src/dbus/marathonpermissionportal.h
    src/dbus/marathonpermissionportal.cpp
    src/marathonpermissionmanager.h
    src/marathonpermissionmanager.cpp
    src/portalmanager.h
    src/portalmanager.cpp
    src/marathonappstoreservice.h
    src/marathonappstoreservice.cpp
    src/contactsmanager.h
    src/contactsmanager.cpp
    src/telephonyservice.h
    src/telephonyservice.cpp
    src/callhistorymanager.h
    src/callhistorymanager.cpp
    src/smsservice.h
    src/smsservice.cpp
    src/medialibrarymanager.h
    src/medialibrarymanager.cpp
    src/musiclibrarymanager.h
    src/musiclibrarymanager.cpp

    src/mpris2controller.h
    src/mpris2controller.cpp
    src/rotationmanager.h
    src/rotationmanager.cpp
    src/locationmanager.h
    src/locationmanager.cpp
    src/hapticmanager.h
    src/hapticmanager.cpp
    src/audioroutingmanager.h
    src/audioroutingmanager.cpp
    src/securitymanager.h
    src/securitymanager.cpp
)

list(APPEND SOURCES
    src/waylandcompositormanager.h
    src/waylandcompositormanager.cpp
)

if(TARGET Qt6::WaylandCompositor)
    list(APPEND SOURCES
        src/waylandcompositor.h
        src/waylandcompositor.cpp
    )
endif()

set(QML_FILES
    qml/Main.qml
    qml/MarathonShell.qml
    qml/utils/Async.qml
    qml/components/MarathonLockScreen.qml
    qml/components/MarathonAppGrid.qml
    qml/components/MarathonNavBar.qml
    qml/components/MarathonStatusBar.qml
    qml/components/MarathonBottomBar.qml
    qml/components/MarathonMessagingHub.qml
    qml/components/MarathonQuickSettings.qml
    qml/components/MarathonTaskSwitcher.qml
    qml/components/MarathonPeek.qml
    qml/components/MarathonHub.qml
    qml/components/MarathonPinScreen.qml
    qml/components/MarathonAppWindow.qml
    qml/components/MarathonPageView.qml
    qml/components/MarathonSearch.qml
    qml/components/WaylandShellSurfaceItem.qml
    qml/components/ui/Button.qml
    qml/components/ui/Input.qml
    qml/components/ui/PageIndicator.qml
    qml/components/ui/Modal.qml
    qml/components/ui/TextInputModal.qml
    qml/components/ui/ListPickerModal.qml
    qml/components/ui/StorageDetailsModal.qml
    qml/components/ui/ConfirmDialog.qml
    qml/components/navigation/InertiaNavBar.qml
    qml/components/NotificationToast.qml
    qml/components/SystemHUD.qml
    qml/components/ScreenshotPreview.qml
    qml/components/BackGestureIndicator.qml
    qml/components/ShareSheet.qml
    qml/components/AppContextMenu.qml
    qml/components/ClipboardManager.qml
    qml/components/ConnectionToast.qml
    qml/components/CompositorConnections.qml
    qml/components/ShellInitialization.qml
    qml/components/MarathonAlarmOverlay.qml
    qml/components/MarathonOOBE.qml
    qml/components/WiFiPasswordDialog.qml
    qml/components/BluetoothPairDialog.qml
    qml/components/ErrorToast.qml
    qml/components/IncomingCallOverlay.qml
    qml/components/VirtualKeyboard.qml
    qml/components/PermissionDialog.qml
    qml/keyboard/Core/MarathonKeyboard.qml
    qml/keyboard/Core/KeyboardPerformance.qml
    qml/keyboard/UI/Key.qml
    qml/keyboard/UI/PredictionBar.qml
    qml/keyboard/UI/LongPressPopup.qml
    qml/keyboard/Layouts/QwertyLayout.qml
    qml/keyboard/Layouts/SymbolLayout.qml
    qml/keyboard/Layouts/EmojiLayout.qml
    qml/keyboard/Layouts/EmailLayout.qml
    qml/keyboard/Layouts/UrlLayout.qml
    qml/keyboard/Layouts/NumberLayout.qml
    qml/keyboard/Layouts/PhoneLayout.qml
    qml/keyboard/Input/InputContext.qml
    qml/keyboard/Data/Dictionary.qml
    qml/keyboard/Data/AutoCorrect.qml
    qml/keyboard/Data/DomainSuggestions.qml
    qml/components/PowerMenu.qml
    qml/components/QuickSettingsTile.qml
    qml/components/MediaPlaybackManager.qml
    qml/apps/template/TemplateApp.qml
    qml/apps/native/NativeAppWindow.qml
    qml/stores/AppStore.qml
    qml/stores/WallpaperStore.qml
    qml/stores/SystemStatusStore.qml
    qml/stores/SystemControlStore.qml
    qml/stores/SessionStore.qml
    qml/stores/UIStore.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/Router.qml
    qml/models/FilteredAppModel.qml
    qml/services/Platform.qml
    qml/services/ServiceBus.qml
    qml/services/PowerManager.qml
    qml/services/NetworkManager.qml
    qml/services/DisplayManager.qml
    qml/services/AudioManager.qml
    qml/services/NotificationService.qml
    qml/services/TelephonyManager.qml
    qml/services/LocationService.qml
    qml/services/SessionManager.qml
    qml/services/AppLauncher.qml
    qml/services/WindowManager.qml
    qml/services/DesktopFileParser.qml
    qml/services/StatusBarIconService.qml
    qml/services/ScreenshotService.qml
    qml/services/HapticService.qml
    qml/services/ClipboardService.qml
    qml/services/NavigationRouter.qml
    qml/services/AppLifecycleManager.qml
    qml/services/DesktopEntryParser.qml
    qml/services/UnifiedSearchService.qml
    qml/services/AppLaunchService.qml
    qml/services/DeepLinkHandler.qml
    qml/services/NotificationHandler.qml
    qml/services/TelephonyIntegration.qml
    qml/services/PowerBatteryHandler.qml
    qml/services/AlarmManager.qml
    qml/services/AmbientLightSensor.qml
    qml/services/ProximitySensor.qml
    qml/services/FlashlightManager.qml
    qml/services/CellularManager.qml
    qml/services/StateManager.qml
)

# Find PAM library for authentication
find_library(PAM_LIBRARY pam)
if(NOT PAM_LIBRARY)
    message(FATAL_ERROR "PAM library not found. Install libpam-dev (Debian/Ubuntu) or pam-devel (Fedora/RHEL)")
endif()
message(STATUS "Found PAM library: ${PAM_LIBRARY}")

qt6_add_executable(marathon-shell ${SOURCES})

# Mark singleton files BEFORE adding QML module
set(SINGLETON_FILES
    qml/stores/AppStore.qml
    qml/stores/WallpaperStore.qml
    qml/stores/SystemStatusStore.qml
    qml/stores/SystemControlStore.qml
    qml/stores/SessionStore.qml
    qml/stores/UIStore.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/Router.qml
    qml/utils/Async.qml
    qml/services/Platform.qml
    qml/services/ServiceBus.qml
    qml/services/PowerManager.qml
    qml/services/NetworkManager.qml
    qml/services/DisplayManager.qml
    qml/services/AudioManager.qml
    qml/services/NotificationService.qml
    qml/services/TelephonyManager.qml
    qml/services/LocationService.qml
    qml/services/SessionManager.qml
    qml/services/AppLauncher.qml
    qml/services/WindowManager.qml
    qml/services/DesktopFileParser.qml
    qml/services/StatusBarIconService.qml
    qml/services/ScreenshotService.qml
    qml/services/HapticService.qml
    qml/services/ClipboardService.qml
    qml/services/NavigationRouter.qml
    qml/services/AppLifecycleManager.qml
    qml/services/DesktopEntryParser.qml
    qml/services/UnifiedSearchService.qml
    qml/services/AppLaunchService.qml
    qml/services/DeepLinkHandler.qml
    qml/services/NotificationHandler.qml
    qml/services/TelephonyIntegration.qml
    qml/services/PowerBatteryHandler.qml
    qml/services/AlarmManager.qml
    qml/services/AmbientLightSensor.qml
    qml/services/ProximitySensor.qml
    qml/services/FlashlightManager.qml
    qml/services/CellularManager.qml
)

foreach(singleton_file ${SINGLETON_FILES})
    set_source_files_properties(${singleton_file} PROPERTIES
        QT_QML_SINGLETON_TYPE TRUE
    )
endforeach()

if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

# Include QML linting module
include(${CMAKE_SOURCE_DIR}/cmake/QMLLint.cmake)

# Set Qt QML policies for Qt 6.5+ compatibility
# QTP0001: Use ':/qt/qml/' as the default resource prefix (required for proper QML module loading)
# QTP0004: Require qmldir files for each directory containing QML files (improves module structure)
if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

# FIX: Use Big Resources for large assets to prevent OOM
# This compiles resources.qrc into a separate object file that handles large data better
qt6_add_big_resources(BIG_RESOURCES resources.qrc)

# Qt6 QML module configuration
qt6_add_qml_module(marathon-shell
    URI MarathonOS.Shell
    VERSION 1.0
    QML_FILES ${QML_FILES}
    RESOURCES
        # resources.qrc  <-- REMOVED from here (handled by big_resources)
        qml/keyboard/Core/qmldir
        qml/keyboard/UI/qmldir
        qml/keyboard/Layouts/qmldir
        qml/keyboard/Input/qmldir
        qml/keyboard/Data/qmldir
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell
)

# Link the big resources to the target
target_sources(marathon-shell PRIVATE ${BIG_RESOURCES})

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-shell ${QML_FILES})
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSEAUDIO REQUIRED libpulse)
target_include_directories(marathon-shell PRIVATE
    ${PULSEAUDIO_INCLUDE_DIRS}
)

find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)

target_link_libraries(marathon-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::Widgets
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::DBus
    Qt6::Multimedia
    Qt6::Network
    Qt6::Sensors
    MarathonCore
    asyncfuture
    marathon-ui-theme
    marathon-ui-containers
    marathon-ui-core
    marathon-ui-controls
    marathon-ui-lists
    marathon-ui-navigation
    marathon-ui-feedback
    marathon-ui-modals
    marathon-ui-effects
    ${PULSEAUDIO_LIBRARIES}
    ${PAM_LIBRARY}
)

# Link additional conditional dependencies

if(TARGET Qt6::WaylandCompositor)
    target_link_libraries(marathon-shell PRIVATE Qt6::WaylandCompositor)
    target_compile_definitions(marathon-shell PRIVATE HAVE_WAYLAND)
endif()

# Link QtDBus and QtSql for telephony and media services
target_link_libraries(marathon-shell PRIVATE Qt6::DBus Qt6::Sql)

if(HAVE_WEBENGINE)
    target_link_libraries(marathon-shell PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(marathon-shell PRIVATE HAVE_WEBENGINE)
endif()

# Link Hunspell for spell-checking
if(HAVE_HUNSPELL)
    target_link_libraries(marathon-shell PRIVATE ${HUNSPELL_LIBRARIES})
    target_include_directories(marathon-shell PRIVATE ${HUNSPELL_INCLUDE_DIRS})
    target_compile_definitions(marathon-shell PRIVATE HAVE_HUNSPELL)
    message(STATUS "Linking Hunspell to marathon-shell")
endif()

# Enable QML Debugging/Profiling
target_compile_definitions(marathon-shell PRIVATE QT_QML_DEBUG)

set_target_properties(marathon-shell PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
    OUTPUT_NAME marathon-shell-bin
)

install(TARGETS marathon-shell
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install QML modules (libraries and plugins)
# MarathonUI modules are installed by marathon-ui/CMakeLists.txt
# No need to install them here
