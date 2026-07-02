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
    src/services/backgroundtaskobserver.h
    src/services/backgroundtaskobserver.cpp
    src/services/cgroupmanager.h
    src/services/cgroupmanager.cpp
    src/services/memorypressuremonitor.h
    src/services/memorypressuremonitor.cpp
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
    src/services/unifiedpushdistributor.h
    src/services/unifiedpushdistributor.cpp
    src/services/marathonntfyclient.h
    src/services/marathonntfyclient.cpp
    src/services/carrierprovisioning.h
    src/services/carrierprovisioning.cpp
    src/services/flatpakmanager.h
    src/services/flatpakmanager.cpp
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
    src/managers/powerkeylistener.h
    src/managers/powerkeylistener.cpp
    src/services/screenshotservicecpp.h
    src/services/screenshotservicecpp.cpp
    src/managers/audiomanagercpp.h
    src/managers/audiomanagercpp.cpp
    src/managers/modemmanagercpp.h
    src/managers/modemmanagercpp.cpp
    src/managers/cellbroadcastmanager.h
    src/managers/cellbroadcastmanager.cpp
    src/managers/sensormanagercpp.h
    src/managers/sensormanagercpp.cpp
    src/managers/settingsmanager.h
    src/managers/settingsmanager.cpp
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
    src/services/updateservice.h
    src/services/updateservice.cpp
    src/services/motiondaemon.h
    src/services/motiondaemon.cpp
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
    src/services/systemstatusstore.h
    src/services/systemstatusstore.cpp
    src/services/systemcontrolstore.h
    src/services/systemcontrolstore.cpp
    src/services/uistore.h
    src/services/uistore.cpp
    src/services/appstore.h
    src/services/appstore.cpp
    src/services/wallpaperstore.h
    src/services/wallpaperstore.cpp
    src/services/router.h
    src/services/router.cpp
    src/services/surfaceregistry.h
    src/services/surfaceregistry.cpp
    src/services/domainsuggestions.h
    src/services/domainsuggestions.cpp
    src/services/emojipredictor.h
    src/services/emojipredictor.cpp
    src/services/phrasepredictor.h
    src/services/phrasepredictor.cpp
    src/services/languagemanager.h
    src/services/languagemanager.cpp
    src/services/dictionary.h
    src/services/dictionary.cpp
    src/services/autocorrect.h
    src/services/autocorrect.cpp
    src/services/inputcontext.h
    src/services/inputcontext.cpp
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
        src/wayland/securitycontextv1.h
        src/wayland/securitycontextv1.cpp
        src/wayland/fifov1.h
        src/wayland/fifov1.cpp
        src/wayland/committimingv1.h
        src/wayland/committimingv1.cpp
        src/wayland/linuxdmabufv1.h
        src/wayland/linuxdmabufv1.cpp
    )

    find_program(WAYLAND_SCANNER wayland-scanner)
    if(WAYLAND_SCANNER)
        # Each custom protocol: <xml-stem> in the protocols dir.
        # wayland-scanner generates a server header + private-code .c
        # in the build dir, which we then add to SOURCES.
        #
        # text-input-unstable-v3 is named the way it is for protocol-
        # version compatibility (it follows the pre-staging naming).
        # Everything else follows the staging naming (foo-vN.xml →
        # foo-vN-server.h, foo-vN.c) which matches the upstream
        # wayland-protocols layout.
        function(marathon_scan_protocol XML_STEM HEADER_STEM)
            set(_xml    ${CMAKE_CURRENT_SOURCE_DIR}/protocols/${XML_STEM}.xml)
            set(_hdr    ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_STEM}-server.h)
            set(_code   ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_STEM}.c)
            add_custom_command(OUTPUT ${_hdr}
                COMMAND ${WAYLAND_SCANNER} server-header  ${_xml} ${_hdr}
                DEPENDS ${_xml})
            add_custom_command(OUTPUT ${_code}
                COMMAND ${WAYLAND_SCANNER} private-code   ${_xml} ${_code}
                DEPENDS ${_xml})
            set(SOURCES ${SOURCES} ${_code} ${_hdr} PARENT_SCOPE)
        endfunction()

        marathon_scan_protocol(text-input-unstable-v3 text-input-unstable-v3)
        marathon_scan_protocol(security-context-v1    security-context-v1)
        marathon_scan_protocol(fifo-v1                fifo-v1)
        marathon_scan_protocol(commit-timing-v1       commit-timing-v1)
        marathon_scan_protocol(linux-dmabuf-v1        linux-dmabuf-v1)
        message(STATUS "Wayland scanner found - enabling custom protocols: text-input-v3, security-context-v1, fifo-v1, commit-timing-v1, linux-dmabuf-v1")
    else()
        message(WARNING "wayland-scanner not found - custom protocols disabled")
    endif()
endif()

set(QML_FILES
    qml/Main.qml
    qml/MarathonShell.qml
    qml/components/AppBackdropBlur.qml
    qml/components/MarathonLockScreen.qml
    qml/components/MarathonLockShortcuts.qml
    qml/components/MarathonAppGrid.qml
    qml/components/MarathonTaskSwitcher.qml
    qml/components/MarathonNavBar.qml
    qml/components/MarathonStatusBar.qml
    qml/components/MarathonBottomBar.qml
    qml/components/MarathonMessagingHub.qml
    qml/components/MarathonQuickSettings.qml
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
    qml/components/MarathonCellBroadcastOverlay.qml
    qml/components/MarathonLockScreenNetworkAgent.qml
    qml/components/MarathonOOBE.qml
    qml/components/WiFiPasswordDialog.qml
    qml/components/BluetoothPairDialog.qml
    qml/components/ErrorToast.qml
    qml/components/IncomingCallOverlay.qml
    qml/components/VirtualKeyboard.qml
    qml/components/PermissionDialog.qml
    qml/keyboard/Core/MarathonKeyboard.qml
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
    qml/components/PowerMenu.qml
    qml/components/QuickSettingsTile.qml
    qml/components/MediaPlaybackManager.qml
    qml/apps/template/TemplateApp.qml
    qml/apps/native/NativeAppWindow.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/models/FilteredAppModel.qml
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
    qml/core/Constants.qml
    qml/core/Logger.qml
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
# QTP0004: for each directory that contains .qml files, qmldir file is generated
if(COMMAND qt_policy)
    # Guard for Droidian (Qt 6.4.2) - these policies are Qt 6.5+ only
    if(Qt6_VERSION VERSION_GREATER_EQUAL "6.5.0")
        qt_policy(SET QTP0001 NEW)
        qt_policy(SET QTP0004 NEW)
    endif()
endif()

# Embed UI resources (icons, wallpapers, fonts) via explicit FILES list.
#
# This used to go through `qt6_add_big_resources(... resources.qrc)` which
# silently dropped every .svg/.png path on the Alpine-edge container build
# (verified by `strings marathon-shell-bin | grep ^qrc:` — only .jpg/.wav
# files made it through). The variable-form qt_add_resources had the same
# symptom: the qrc paths get compiled, but only the .jpg and .wav data
# arrays survive linking. Hypothesis: the autorcc machinery from
# qt_add_qml_module collides with the qrc-form qt_add_resources on the
# same target. The TARGET form below (explicit FILES, no .qrc) sidesteps
# the conflict entirely and is the documented modern API.
qt_add_resources(marathon-shell "shell_images"
    PREFIX "/images"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources/images"
    FILES
        resources/images/marathon.png
        resources/images/phone.svg
        resources/images/messages.svg
        resources/images/mail.svg
        resources/images/browser.svg
        resources/images/camera.svg
        resources/images/settings.svg
        resources/images/calendar.svg
        resources/images/clock.svg
        resources/images/music.svg
        resources/images/gallery.svg
        resources/images/maps.svg
        resources/images/calculator.svg
        resources/images/notes.svg
        resources/images/store.svg
        resources/images/marathon.svg
        resources/images/wallet.svg
        resources/images/health.svg
        resources/images/weather.svg
        resources/images/voice.svg
        resources/images/contacts.svg
        resources/images/files.svg
        resources/images/disconnect.svg
)
qt_add_resources(marathon-shell "shell_wallpapers"
    PREFIX "/wallpapers"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources/wallpapers"
    FILES
        resources/wallpapers/slate-aurora.svg
        resources/wallpapers/carbon.svg
        resources/wallpapers/contour.svg
        resources/wallpapers/dawn.svg
        resources/wallpapers/halftone.svg
        resources/wallpapers/indigo-dusk.svg
        resources/wallpapers/long-run.svg
        resources/wallpapers/mesh.svg
        resources/wallpapers/pulse.svg
        resources/wallpapers/striae.svg
        resources/wallpapers/stride.svg
        resources/wallpapers/track.svg
        resources/wallpapers/tundra.svg
        resources/wallpapers/dither-noise.png
)
# Fonts go via a dedicated qrc to preserve `alias=` mappings — the FILES
# form of qt_add_resources can't rename embedded paths, and the brackets
# in `Sora[wght].ttf` further confuse the prefix-mapped lookup. Using a
# qrc with `<file alias="Sora.ttf">…</file>` keeps the FontLoader paths
# stable across builds.
qt_add_resources(SHELL_FONTS resources-fonts.qrc)
target_sources(marathon-shell PRIVATE ${SHELL_FONTS})
# Sounds stay in resources.qrc with the variable-output form because the
# .wav blobs (69 MB) DO actually land in the binary today. Keep them out
# of the qml-module target to avoid recompiling the giant initializer
# every time a QML file changes.
qt_add_resources(SHELL_SOUNDS resources.qrc)

# Qt6 QML module configuration
qt6_add_qml_module(marathon-shell
    URI MarathonOS.Shell
    VERSION 1.0
    IMPORTS
        MarathonUI.Theme
        MarathonUI.Core
        MarathonUI.Controls
        MarathonUI.Lists
        MarathonUI.Navigation
        MarathonUI.Feedback
        MarathonUI.Modals
        MarathonUI.Effects
        MarathonUI.Containers
    QML_FILES ${QML_FILES}
    SOURCES
        src/services/sessionstore.cpp
        src/services/sessionstore.h
        src/services/systemstatusstore.cpp
        src/services/systemstatusstore.h
        src/services/systemcontrolstore.cpp
        src/services/systemcontrolstore.h
        src/services/uistore.cpp
        src/services/uistore.h
        src/services/appstore.cpp
        src/services/appstore.h
        src/services/wallpaperstore.cpp
        src/services/wallpaperstore.h
        src/services/router.cpp
        src/services/router.h
        src/services/surfaceregistry.cpp
        src/services/surfaceregistry.h
        src/services/domainsuggestions.cpp
        src/services/domainsuggestions.h
        src/services/emojipredictor.cpp
        src/services/emojipredictor.h
        src/services/phrasepredictor.cpp
        src/services/phrasepredictor.h
        src/services/languagemanager.cpp
        src/services/languagemanager.h
        src/services/dictionary.cpp
        src/services/dictionary.h
        src/services/autocorrect.cpp
        src/services/autocorrect.h
        src/services/inputcontext.cpp
        src/services/inputcontext.h
        src/managers/hapticmanager.cpp
        src/managers/hapticmanager.h
        src/managers/settingsmanager.cpp
        src/managers/settingsmanager.h
        src/managers/mpris2controller.cpp
        src/managers/mpris2controller.h
        src/marathonpermissionmanager.cpp
        src/marathonpermissionmanager.h
        src/models/notificationmodel.cpp
        src/models/notificationmodel.h
        src/models/taskmodel.cpp
        src/models/taskmodel.h
        src/managers/networkmanagercpp.cpp
        src/managers/networkmanagercpp.h
        src/managers/powermanagercpp.cpp
        src/managers/powermanagercpp.h
        src/managers/displaymanagercpp.cpp
        src/managers/displaymanagercpp.h
        src/managers/audiomanagercpp.cpp
        src/managers/audiomanagercpp.h
        src/managers/securitymanager.cpp
        src/managers/securitymanager.h
        src/services/applaunchservice.cpp
        src/services/applaunchservice.h
        src/services/applifecyclemanager.cpp
        src/services/applifecyclemanager.h
        src/services/notificationservicecpp.cpp
        src/services/notificationservicecpp.h
        src/controllers/powerpolicycontroller.cpp
        src/controllers/powerpolicycontroller.h
        src/controllers/displaypolicycontroller.cpp
        src/controllers/displaypolicycontroller.h
        src/controllers/audiopolicycontroller.cpp
        src/controllers/audiopolicycontroller.h
    RESOURCES ${JSON_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell
)

file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/qmllint")

set_property(TARGET marathon-shell PROPERTY QT_QML_IMPORT_PATH
    "${CMAKE_BINARY_DIR}/qmllint"
    "${CMAKE_BINARY_DIR}"
    "${CMAKE_BINARY_DIR}/shell/qml"
)

# Link the big resources (sounds-only qrc) to the target
target_sources(marathon-shell PRIVATE ${SHELL_SOUNDS})

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-shell ${QML_FILES})
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSEAUDIO REQUIRED libpulse)
pkg_check_modules(PIPEWIRE REQUIRED libpipewire-0.3)
# libdrm: direct atomic CRTC ACTIVE toggle for the Doze display-off path
# (WaylandCompositor::setDisplayPowerState). Present via mesa-dev on the
# Alpine build root; the shell already holds the DRM master fd from eglfs.
pkg_check_modules(LIBDRM REQUIRED libdrm)
target_include_directories(marathon-shell PRIVATE
    ${PULSEAUDIO_INCLUDE_DIRS}
    ${PIPEWIRE_INCLUDE_DIRS}
    ${LIBDRM_INCLUDE_DIRS}
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
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::DBus
    Qt6::Multimedia
    Qt6::Network
    Qt6::Sensors
    Qt6::WebSockets
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
    ${PIPEWIRE_LIBRARIES}
    ${LIBDRM_LIBRARIES}
    ${PAM_LIBRARY}
    lunasvg
)

# MotionDaemon needs the vendored Oxford step-counting algorithm.
if(TARGET oxford-step-counter)
    target_link_libraries(marathon-shell PRIVATE oxford-step-counter)
endif()

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

# NOTE: Qt WebEngine intentionally NOT linked into the shell.
# Maps / Browser / Email each import QtWebEngine in their own QML; they
# run out-of-process under marathon-app-runner, which is the binary that
# owns the Chromium runtime cost (gated on manifest requiresQtModules).
# See tools/marathon-app-runner/CMakeLists.txt + main.cpp.

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

# Enable QML Debugging/Profiling — Debug builds only. QT_QML_DEBUG opens a
# TCP debug port (off by default but the macro pulls in the QML profiler
# runtime + emits "QML debugging is enabled. Only use this in a safe
# environment." on every shell start) which is inappropriate for the
# Marathon shell shipping in a production image.
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_definitions(marathon-shell PRIVATE QT_QML_DEBUG)
    message(STATUS "QML debugging enabled (Debug build)")
endif()

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

# qt6_add_qml_module bakes `prefer :/qt/qml/MarathonOS/Shell/` into the
# generated qmldir at ${CMAKE_CURRENT_BINARY_DIR}/qml/MarathonOS/Shell/qmldir.
# That's correct for marathon-shell-bin (uses its embedded qrc copies of
# the .qml files at runtime). But it breaks marathon-app-runner: when an
# app pulls in a shared shell component (e.g. WiFiPasswordDialog →
# Constants), Qt follows the prefer line into the app-runner's qrc where
# those files don't exist. Strip the prefer line from the BUILD output so
# the install copies a clean qmldir; the shell binary doesn't consult
# this file at runtime so the strip is safe for it.
# NOTE: the installed MarathonOS.Shell/qmldir carries a
# `prefer :/qt/qml/MarathonOS/Shell/` directive that tells Qt to use the
# shell binary's qrc copies of the .qml files. That's right for the
# shell binary itself but breaks marathon-app-runner (the qrc only
# exists in marathon-shell-bin's address space). The APKBUILD's
# package() step strips this directive post-install, alongside the
# equivalent strip it already does for MarathonUI sub-modules.
