set(SOURCES
    main.cpp
    src/components/desktopfileparser.h
    src/components/desktopfileparser.cpp
    src/components/lunasvgimageprovider.h
    src/components/lunasvgimageprovider.cpp
    src/models/appmodel.h
    src/models/appmodel.cpp
    src/services/applaunchservice.h
    src/services/applaunchservice.cpp
    src/services/applifecyclemanager.h
    src/services/applifecyclemanager.cpp
    src/ipc/shellipcserver.h
    src/ipc/shellipcserver.cpp
    src/ipc/shellservices.h
    src/ipc/shellservices.cpp
    src/models/taskmodel.h
    src/models/taskmodel.cpp
    src/services/statemanagercpp.h
    src/services/statemanagercpp.cpp
    src/services/unifiedsearchservicecpp.h
    src/services/unifiedsearchservicecpp.cpp
    src/models/notificationmodel.h
    src/models/notificationmodel.cpp
    src/services/notificationhandlercpp.h
    src/services/notificationhandlercpp.cpp
    src/services/notificationservicecpp.h
    src/services/notificationservicecpp.cpp
    src/services/telephonyintegrationcpp.h
    src/services/telephonyintegrationcpp.cpp
    src/components/crashhandler.h
    src/components/crashhandler.cpp
    qml/keyboard/Data/WordEngine.h
    qml/keyboard/Data/WordEngine.cpp
    qml/keyboard/Data/WordTrie.h
    qml/keyboard/Data/WordTrie.cpp
    src/managers/networkmanagercpp.h
    src/managers/networkmanagercpp.cpp
    src/managers/powermanagercpp.h
    src/managers/powermanagercpp.cpp
    src/controllers/powerpolicycontroller.h
    src/controllers/powerpolicycontroller.cpp
    src/services/powerbatteryhandlercpp.h
    src/services/powerbatteryhandlercpp.cpp
    src/controllers/displaypolicycontroller.h
    src/controllers/displaypolicycontroller.cpp
    src/managers/displaymanagercpp.h
    src/managers/displaymanagercpp.cpp
    src/services/screenshotservicecpp.h
    src/services/screenshotservicecpp.cpp
    src/managers/audiomanagercpp.h
    src/managers/audiomanagercpp.cpp
    src/managers/modemmanagercpp.h
    src/managers/modemmanagercpp.cpp
    src/managers/sensormanagercpp.h
    src/managers/sensormanagercpp.cpp
    src/managers/settingsmanager.h
    src/managers/settingsmanager.cpp
    src/managers/platform.h
    src/managers/platformcpp.h
    src/services/navigationroutercpp.h
    src/services/navigationroutercpp.cpp
    src/managers/bluetoothmanager.h
    src/managers/bluetoothmanager.cpp
    src/components/bluetoothagent.h
    src/components/bluetoothagent.cpp
    src/managers/marathoninputmethodengine.h
    src/managers/marathoninputmethodengine.cpp
    src/managers/rtscheduler.h
    src/managers/rtscheduler.cpp
    src/dbus/freedesktopnotifications.h
    src/dbus/freedesktopnotifications.cpp
    src/dbus/notificationdatabase.h
    src/dbus/notificationdatabase.cpp
    src/marathonpermissionmanager.h
    src/marathonpermissionmanager.cpp
    src/components/portalmanager.h
    src/components/portalmanager.cpp
    src/services/marathonappstoreservice.h
    src/services/marathonappstoreservice.cpp
    # (Contacts/SMS/Telephony/Media/Music moved to MarathonServices)

    src/managers/mpris2controller.h
    src/managers/mpris2controller.cpp
    src/managers/rotationmanager.h
    src/managers/rotationmanager.cpp
    src/managers/locationmanager.h
    src/managers/locationmanager.cpp
    src/managers/clipboardmanagercpp.h
    src/managers/clipboardmanagercpp.cpp
    src/managers/hapticmanager.h
    src/managers/hapticmanager.cpp
    src/managers/alarmmanagercpp.h
    src/managers/alarmmanagercpp.cpp
    src/services/statusbariconservicecpp.h
    src/services/statusbariconservicecpp.cpp
    src/managers/flashlightmanagercpp.h
    src/managers/flashlightmanagercpp.cpp
    src/controllers/audioroutingmanager.h
    src/controllers/audioroutingmanager.cpp
    src/controllers/audiopolicycontroller.h
    src/controllers/audiopolicycontroller.cpp
    src/managers/securitymanager.h
    src/managers/securitymanager.cpp
    src/managers/screenmetrics.h
    src/managers/screenmetrics.cpp
)

list(APPEND SOURCES
    src/wayland/waylandcompositormanager.h
    src/wayland/waylandcompositormanager.cpp
    src/managers/cursormanager.h
    src/managers/cursormanager.cpp
)

if(TARGET Qt6::WaylandCompositor)
    list(APPEND SOURCES
        src/wayland/waylandcompositor.h
        src/wayland/waylandcompositor.cpp
        src/wayland/textinputv3.h
        src/wayland/textinputv3.cpp
    )

    find_program(WAYLAND_SCANNER wayland-scanner)
    if(WAYLAND_SCANNER)
        set(TEXT_INPUT_V3_XML ${CMAKE_CURRENT_SOURCE_DIR}/protocols/text-input-unstable-v3.xml)
        set(TEXT_INPUT_V3_SERVER_H ${CMAKE_CURRENT_BINARY_DIR}/text-input-unstable-v3-server.h)
        set(TEXT_INPUT_V3_CODE ${CMAKE_CURRENT_BINARY_DIR}/text-input-unstable-v3.c)

        add_custom_command(
            OUTPUT ${TEXT_INPUT_V3_SERVER_H}
            COMMAND ${WAYLAND_SCANNER} server-header ${TEXT_INPUT_V3_XML} ${TEXT_INPUT_V3_SERVER_H}
            DEPENDS ${TEXT_INPUT_V3_XML}
        )
        add_custom_command(
            OUTPUT ${TEXT_INPUT_V3_CODE}
            COMMAND ${WAYLAND_SCANNER} private-code ${TEXT_INPUT_V3_XML} ${TEXT_INPUT_V3_CODE}
            DEPENDS ${TEXT_INPUT_V3_XML}
        )

        list(APPEND SOURCES ${TEXT_INPUT_V3_CODE} ${TEXT_INPUT_V3_SERVER_H})
        message(STATUS "Wayland scanner found - enabling text-input-v3 protocol")
    else()
        message(WARNING "wayland-scanner not found - custom protocols disabled")
    endif()
endif()

set(QML_FILES
    qml/Main.qml
    qml/MarathonShell.qml
    qml/components/MarathonLockScreen.qml
    qml/components/MarathonAppGrid.qml
    qml/components/MarathonNavBar.qml
    qml/components/MarathonStatusBar.qml
    qml/components/MarathonBottomBar.qml
    qml/components/MarathonMessagingHub.qml
    qml/components/MarathonQuickSettings.qml
    qml/components/MarathonTaskSwitcher.qml
    qml/components/TaskCard.qml
    qml/components/TaskPageIndicator.qml
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
    qml/keyboard/Core/LanguageManager.qml
    qml/keyboard/UI/Key.qml
    qml/keyboard/UI/PredictionBar.qml
    qml/keyboard/UI/LongPressPopup.qml
    qml/keyboard/UI/LanguageSelector.qml
    qml/keyboard/Layouts/QwertyLayout.qml
    qml/keyboard/Layouts/DynamicLayout.qml
    qml/keyboard/Layouts/SymbolLayout.qml
    qml/keyboard/Layouts/EmojiLayout.qml
    qml/keyboard/Layouts/EmailLayout.qml
    qml/keyboard/Layouts/UrlLayout.qml
    qml/keyboard/Layouts/NumberLayout.qml
    qml/keyboard/Layouts/PhoneLayout.qml
    qml/keyboard/Layouts/TerminalLayout.qml
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
    src/services/sessionstore.h
    src/services/sessionstore.cpp
    qml/stores/UIStore.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/SurfaceRegistry.qml
    qml/core/Router.qml
    qml/models/FilteredAppModel.qml
    qml/services/CalendarWorker.js
)

set(JSON_FILES
    qml/keyboard/Layouts/languages/en_US.json
    qml/keyboard/Layouts/languages/fr_FR.json
    qml/keyboard/Layouts/languages/de_DE.json
    qml/keyboard/Layouts/languages/es_ES.json
    qml/keyboard/Layouts/languages/pt_BR.json
    qml/keyboard/Layouts/languages/it_IT.json
    qml/keyboard/Layouts/languages/ru_RU.json
    qml/keyboard/Layouts/languages/ar_SA.json
    qml/keyboard/Layouts/languages/zh_CN.json
    qml/keyboard/Layouts/languages/ja_JP.json
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
    qml/stores/UIStore.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/SurfaceRegistry.qml
    qml/core/Router.qml
    qml/keyboard/Core/LanguageManager.qml
    qml/keyboard/Data/Dictionary.qml
    qml/keyboard/Data/AutoCorrect.qml
)

foreach(singleton_file ${SINGLETON_FILES})
    set_source_files_properties(${singleton_file} PROPERTIES
        QT_QML_SINGLETON_TYPE TRUE
    )
endforeach()

set_source_files_properties(qml/services/CalendarWorker.js PROPERTIES
    QT_QML_SKIP_QMLDIR_ENTRY TRUE
)

if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

# Include QML linting module
include(${CMAKE_SOURCE_DIR}/cmake/QMLLint.cmake)

# Set Qt QML policies for Qt 6.5+ compatibility
# QTP0001: Use ':/qt/qml/' as the default resource prefix (required for proper QML module loading)
# QTP0004: for each directory that contains .qml files, qmldir file is generated
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
    SOURCES
        src/services/sessionstore.cpp
        src/services/sessionstore.h
    RESOURCES ${JSON_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell
)

file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/qmllint")

set_property(TARGET marathon-shell PROPERTY QT_QML_IMPORT_PATH
    "${CMAKE_BINARY_DIR}/qmllint"
    "${CMAKE_BINARY_DIR}"
    "${CMAKE_BINARY_DIR}/shell/qml"
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
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/components
    ${CMAKE_CURRENT_SOURCE_DIR}/src/services
    ${CMAKE_CURRENT_SOURCE_DIR}/src/managers
    ${CMAKE_CURRENT_SOURCE_DIR}/src/models
    ${CMAKE_CURRENT_SOURCE_DIR}/src/controllers
)

find_package(Qt6 REQUIRED COMPONENTS Gui)

# GuiPrivate is Qt-internal; only link it when enabled and available.
if(TARGET Qt6::GuiPrivate)
    target_link_libraries(marathon-shell PRIVATE Qt6::GuiPrivate)
    target_compile_definitions(marathon-shell PRIVATE MARATHON_HAVE_QT_GUI_PRIVATE=1)
else()
    target_compile_definitions(marathon-shell PRIVATE MARATHON_HAVE_QT_GUI_PRIVATE=0)
endif()

target_link_libraries(marathon-shell PRIVATE
    Qt6::Core
    Qt6::Gui
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
    MarathonServices
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
    lunasvg
)

# Link additional conditional dependencies

if(TARGET Qt6::WaylandCompositor)
    target_link_libraries(marathon-shell PRIVATE Qt6::WaylandCompositor)
    target_compile_definitions(marathon-shell PRIVATE HAVE_WAYLAND)

    # Link private module for text-input-v3 access
    if(TARGET Qt6::WaylandCompositorPrivate)
        target_link_libraries(marathon-shell PRIVATE Qt6::WaylandCompositorPrivate)
        target_compile_definitions(marathon-shell PRIVATE HAVE_WAYLAND_PRIVATE)
    endif()
endif()

# Link QtDBus and QtSql for telephony and media services
target_link_libraries(marathon-shell PRIVATE Qt6::DBus Qt6::Sql)

if(HAVE_WEBENGINE)
    target_link_libraries(marathon-shell PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(marathon-shell PRIVATE HAVE_WEBENGINE)
endif()

# Link Hunspell for spell-checking
pkg_check_modules(HUNSPELL hunspell)
if(HUNSPELL_FOUND)
    set(HAVE_HUNSPELL TRUE)
endif()

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

# Install MarathonOS.Shell module for marathon-app-runner to find it
if(CMAKE_INSTALL_PREFIX STREQUAL "/usr" OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local")
    set(SHELL_QML_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/lib/qt6/qml")
    
    install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/qml/MarathonOS/
        DESTINATION ${SHELL_QML_INSTALL_DIR}/MarathonOS
        FILES_MATCHING
        PATTERN "qmldir"
        PATTERN "*.qmltypes"
        PATTERN "*.qml"
        PATTERN "*.js"
        PATTERN "*.so"
    )
endif()
