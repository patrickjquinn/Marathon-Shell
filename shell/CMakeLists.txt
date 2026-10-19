set(SOURCES
    main.cpp
    src/diag/fpsmonitor.h
    src/diag/fpsmonitor.cpp
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
    src/services/processstopper.h
    src/services/processstopper.cpp
    src/managers/drmmasterwait.h
    src/managers/drmmasterwait.cpp
    src/services/memorypressuremonitor.h
    src/services/memorypressuremonitor.cpp
    src/ipc/shellipcserver.h
    src/ipc/shellipcserver.cpp
    src/ipc/permissionauth.h
    src/ipc/shellservices.h
    src/ipc/shellservices.cpp
    src/ipc/shellkeelactions.h
    src/ipc/shellkeelactions.cpp
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner/ipc/dbusnormalize.cpp
    src/models/taskmodel.h
    src/models/taskmodel.cpp
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
    src/managers/waketimers.h
    src/managers/waketimers.cpp
    src/controllers/powerpolicycontroller.h
    src/controllers/powerpolicycontroller.cpp
    src/services/powerbatteryhandlercpp.h
    src/services/powerbatteryhandlercpp.cpp
    src/controllers/displaypolicycontroller.h
    src/controllers/displaypolicycontroller.cpp
    src/managers/displaymanagercpp.h
    src/managers/displaymanagercpp.cpp
    src/managers/deviceprofile.h
    src/managers/deviceprofile.cpp
    src/managers/powerkeylistener.h
    src/managers/powerkeylistener.cpp
    src/services/screenshotservicecpp.h
    src/services/screenshotservicecpp.cpp
    src/managers/audiomanagercpp.h
    src/managers/audiomanagercpp.cpp
    src/managers/sinkvolume.h
    src/managers/sinkvolume.cpp
    src/managers/mediarole.h
    src/managers/audiodclient.h
    src/managers/audiodclient.cpp
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
    src/managers/marathoninputcontext.cpp
    src/managers/rtscheduler.h
    src/managers/rtscheduler.cpp
    src/dbus/freedesktopnotifications.h
    src/dbus/freedesktopnotifications.cpp
    src/services/notificationtarget.h
    src/services/notificationtarget.cpp
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
    src/services/updatenotifier.h
    src/services/updatenotifier.cpp
    src/services/factoryreset.h
    src/services/factoryreset.cpp
    src/services/sysupdatebackend.h
    src/services/sysupdatebackend.cpp
    src/services/motiondaemon.h
    src/services/motiondaemon.cpp
    src/services/inputboost.h
    src/services/inputboost.cpp
    src/services/wakeonkeyfilter.h
    src/services/wakeonkeyfilter.cpp
    src/services/waketouchfilter.h
    src/services/waketouchfilter.cpp
    src/services/pilotclient.h
    src/services/pilotclient.cpp
    src/services/weatherclient.h
    src/services/weatherclient.cpp
    src/services/automatictimezone.h
    src/services/automatictimezone.cpp
    # (Contacts/SMS/Telephony/Media/Music moved to MarathonServices)

    src/managers/mpris2controller.h
    src/managers/mpris2controller.cpp
    src/managers/rotationmanager.h
    src/managers/rotationmanager.cpp
    src/managers/locationmanager.h
    src/managers/locationmanager.cpp
    src/managers/geoclueagent.h
    src/managers/geoclueagent.cpp
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
    src/services/foregroundapp.h
    src/services/foregroundapp.cpp
    src/services/shareservice.h
    src/services/shareservice.cpp
    src/services/appstore.h
    src/services/appstore.cpp
    src/services/wallpaperstore.h
    src/services/wallpaperstore.cpp
    src/services/router.h
    src/services/router.cpp
    src/services/ambiencederivation.cpp
    src/services/ambienceservice.cpp
    src/services/ngfservice.cpp
    src/services/toolkittheme.h
    src/services/toolkittheme.cpp
    src/services/toolkitthemewriter.h
    src/services/toolkitthemewriter.cpp
    src/dbus/portalsettings.cpp
    src/dbus/portalfilechooser.h
    src/dbus/portalfilechooser.cpp
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
    src/services/remotetextinput.h
    src/services/remotetextinput.cpp
    src/managers/flashlightmanagercpp.h
    src/managers/flashlightmanagercpp.cpp
    src/controllers/audioroutingmanager.h
    src/controllers/audioroutingmanager.cpp
    src/controllers/audiopolicycontroller.h
    src/controllers/audiopolicycontroller.cpp
    src/managers/securitymanager.h
    src/managers/securitymanager.cpp
    src/managers/dataencryption.h
    src/managers/dataencryption.cpp
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
        src/wayland/securitycontextv1.h
        src/wayland/securitycontextv1.cpp
        src/wayland/fifov1.h
        src/wayland/fifov1.cpp
        src/wayland/committimingv1.h
        src/wayland/committimingv1.cpp
        src/wayland/linuxdmabufv1.h
        src/wayland/linuxdmabufv1.cpp
        src/wayland/wldrm.h
        src/wayland/wldrm.cpp
        src/wayland/nativeclientscale.h
        src/wayland/nativeclientscale.cpp
        src/wayland/xdgactivationv1.h
        src/wayland/xdgactivationv1.cpp
        src/wayland/marathonsurfacev1.h
        src/wayland/marathonsurfacev1.cpp
        src/wayland/toplevelconfigure.h
        src/wayland/toplevelconfigure.cpp
        src/wayland/remotetextinputtarget.h
        src/wayland/remotetextinputtarget.cpp
    )

    find_program(WAYLAND_SCANNER wayland-scanner)
    if(WAYLAND_SCANNER)
        # Each custom protocol: <xml-stem> in the protocols dir.
        # wayland-scanner generates a server header + private-code .c
        # in the build dir, which we then add to SOURCES.
        #
        # Each follows the staging naming (foo-vN.xml → foo-vN-server.h,
        # foo-vN.c), which matches the upstream wayland-protocols layout.
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

        marathon_scan_protocol(security-context-v1    security-context-v1)
        marathon_scan_protocol(fifo-v1                fifo-v1)
        marathon_scan_protocol(commit-timing-v1       commit-timing-v1)
        marathon_scan_protocol(linux-dmabuf-v1        linux-dmabuf-v1)
        marathon_scan_protocol(wayland-drm            wayland-drm)
        marathon_scan_protocol(fractional-scale-v1    fractional-scale-v1)
        marathon_scan_protocol(xdg-activation-v1      xdg-activation-v1)
        # Qt does not export the C xdg_toplevel_interface marathon-surface-v1 references.
        marathon_scan_protocol(xdg-shell              xdg-shell)
        marathon_scan_protocol(marathon-surface-v1    marathon-surface-v1)
        message(STATUS "Wayland scanner found - enabling custom protocols: text-input-v3, security-context-v1, fifo-v1, commit-timing-v1, linux-dmabuf-v1, wl_drm, fractional-scale-v1, xdg-activation-v1, marathon-surface-v1")
    else()
        message(WARNING "wayland-scanner not found - custom protocols disabled")
    endif()
endif()

set(QML_FILES
    qml/Main.qml
    qml/MarathonShell.qml
    qml/components/AppBackdropBlur.qml
    qml/components/MarathonLockScreen.qml
    qml/components/MarathonAppGrid.qml
    qml/components/MarathonTaskSwitcher.qml
    qml/components/MarathonNavBar.qml
    qml/components/PilotEdgeGlow.qml
    qml/components/MarathonStatusBar.qml
    qml/components/MarathonBottomBar.qml
    qml/components/MarathonQuickSettings.qml
    qml/components/TaskCard.qml
    qml/components/TaskPageIndicator.qml
    qml/components/MarathonPeek.qml
    qml/components/MarathonHub.qml
    qml/components/HubWeather.qml
    qml/components/WeatherHourlyChart.qml
    qml/components/WeatherSheet.qml
    qml/components/WeatherTile.qml
    qml/components/MarathonPinScreen.qml
    qml/components/MarathonAppWindow.qml
    qml/components/KeelAmbienceBackground.qml
    qml/components/KeelCoverView.qml
    qml/components/KeelDialogLayer.qml
    qml/components/MarathonPageView.qml
    qml/components/MarathonSearch.qml
    qml/components/WaylandShellSurfaceItem.qml
    qml/components/ui/ConfirmDialog.qml
    qml/components/NotificationToast.qml
    qml/components/SystemHUD.qml
    qml/components/ScreenshotPreview.qml
    qml/components/AppContextMenu.qml
    qml/components/ClipboardManager.qml
    qml/components/ConnectionToast.qml
    qml/components/AppToast.qml
    qml/components/ShareSheet.qml
    qml/components/FilePickerSheet.qml
    qml/components/ShellInitialization.qml
    qml/components/MarathonAlarmOverlay.qml
    qml/components/MarathonCellBroadcastOverlay.qml
    qml/components/MarathonLockScreenNetworkAgent.qml
    qml/components/MarathonOOBE.qml
    qml/components/WiFiPasswordDialog.qml
    qml/components/ErrorToast.qml
    qml/components/IncomingCallOverlay.qml
    qml/components/VirtualKeyboard.qml
    qml/components/PermissionDialog.qml
    qml/keyboard/Core/MarathonKeyboard.qml
    qml/keyboard/UI/Key.qml
    qml/keyboard/UI/PredictionBar.qml
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
    qml/components/MediaPlaybackManager.qml
    qml/apps/native/NativeAppWindow.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/AmbienceController.qml
    qml/core/WindowOrigins.qml
    qml/models/FilteredAppModel.qml
    qml/theme/MColors.qml
    qml/theme/MTypography.qml
    qml/theme/MSpacing.qml
    qml/theme/MRadius.qml
    qml/theme/MElevation.qml
    qml/theme/MMotion.qml
    qml/theme/MBlur.qml
    qml/ui/GlyphIcon.qml
    qml/ui/MApp.qml
    qml/ui/MAppIcon.qml
    qml/ui/MCircularIconButton.qml
    qml/ui/MEntrance.qml
    qml/ui/MGlass.qml
    qml/ui/MGlassBackdrop.qml
    qml/ui/MGlassPlatter.qml
    qml/ui/MHaptics.qml
    qml/ui/MHubRow.qml
    qml/ui/MMarathonMark.qml
    qml/ui/MNowBar.qml
    qml/ui/MPhoneNumber.qml
    qml/ui/MQSSlider.qml
    qml/ui/MQSTile.qml
    qml/ui/MRipple.qml
    qml/ui/MTabBar.qml
    qml/ui/MTopHairline.qml
    qml/ui/NotificationActions.qml
    qml/ui/NotificationIcon.qml
    qml/ui/PhosphorGlyphs.js
    qml/core/Agenda.js
    qml/core/BatteryWarning.js
    qml/core/Weather.js
    qml/core/LauncherGrid.js
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

set(UI_RESOURCES
    qml/theme/fonts/Sora.ttf
    qml/theme/fonts/Sora-Thin.ttf
    qml/theme/fonts/Sora-ExtraLight.ttf
    qml/theme/fonts/Sora-Light.ttf
    qml/theme/fonts/Sora-Regular.ttf
    qml/theme/fonts/Sora-Medium.ttf
    qml/theme/fonts/Sora-SemiBold.ttf
    qml/theme/fonts/Sora-Bold.ttf
    qml/theme/fonts/Sora-ExtraBold.ttf
    qml/theme/fonts/JetBrainsMono-Medium.ttf
    qml/ui/fonts/Phosphor-Thin.ttf
    qml/ui/fonts/Phosphor-Bold.ttf
)

# Find PAM library for authentication
find_library(PAM_LIBRARY pam)
if(NOT PAM_LIBRARY)
    message(FATAL_ERROR "PAM library not found. Install libpam-dev (Debian/Ubuntu) or pam-devel (Fedora/RHEL)")
endif()
message(STATUS "Found PAM library: ${PAM_LIBRARY}")

qt6_add_executable(marathon-shell ${SOURCES})
# Settings > About; packages pass -DMARATHON_VERSION=pkgver-rpkgrel.
if(NOT DEFINED MARATHON_VERSION)
    set(MARATHON_VERSION "${PROJECT_VERSION}")
endif()
target_compile_definitions(marathon-shell PRIVATE MARATHON_VERSION="${MARATHON_VERSION}")
# A static plugin compiled into the shell; Q_IMPORT_PLUGIN in main.cpp.
set_source_files_properties(src/managers/marathoninputcontext.cpp PROPERTIES
    COMPILE_DEFINITIONS QT_STATICPLUGIN)

# Mark singleton files BEFORE adding QML module
set(SINGLETON_FILES
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/WindowOrigins.qml
    qml/theme/MColors.qml
    qml/theme/MTypography.qml
    qml/theme/MSpacing.qml
    qml/theme/MRadius.qml
    qml/theme/MElevation.qml
    qml/theme/MMotion.qml
    qml/theme/MBlur.qml
    qml/ui/MHaptics.qml
    qml/ui/MPhoneNumber.qml
)

foreach(singleton_file ${SINGLETON_FILES})
    set_source_files_properties(${singleton_file} PROPERTIES
        QT_QML_SINGLETON_TYPE TRUE
    )
endforeach()
# Imported by path; a qmldir entry makes the module ambiguous.
set_source_files_properties(qml/ui/PhosphorGlyphs.js qml/core/Agenda.js qml/core/LauncherGrid.js
    qml/core/BatteryWarning.js qml/core/Weather.js PROPERTIES
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
        resources/images/camera.svg
        resources/images/calendar.svg
)
# Baked with shaders/build-shaders.sh; the device build roots have no qsb.
qt_add_resources(marathon-shell "shell_shaders"
    PREFIX "/marathon/shaders"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
    FILES
        shaders/windowcorner.vert.qsb
        shaders/windowcorner.frag.qsb
        shaders/glassplatter.frag.qsb
)
qt_add_resources(marathon-shell "shell_keel_actions"
    PREFIX "/keel"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/dbus"
    FILES dbus/keel-actions.json
)
qt_add_resources(marathon-shell "shell_wallpapers"
    PREFIX "/wallpapers"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources/wallpapers"
    FILES
        resources/wallpapers/meridian.jpg
        resources/wallpapers/aurora-myvatn.jpg
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
        src/services/gesturetracker.cpp
        src/services/gesturetracker.h
        src/components/windowtexturegeometry.h
        src/components/windowtextureitem.cpp
        src/components/windowtextureitem.h
        src/services/ambiencederivation.cpp
        src/services/ambiencederivation.h
        src/services/ambienceservice.cpp
        src/services/ambienceservice.h
        src/services/ngfservice.cpp
        src/services/ngfservice.h
        src/dbus/portalsettings.cpp
        src/dbus/portalsettings.h
        src/services/surfaceregistry.cpp
        src/services/surfaceregistry.h
        src/services/pilotclient.cpp
        src/services/pilotclient.h
        src/services/weatherclient.cpp
        src/services/weatherclient.h
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
        src/models/filechoosermodel.cpp
        src/models/filechoosermodel.h
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
    RESOURCES ${JSON_FILES} ${UI_RESOURCES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell
)

file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/qmllint")

set(_shell_qml_import_path
    "${CMAKE_BINARY_DIR}/qmllint"
    "${CMAKE_BINARY_DIR}"
    "${CMAKE_BINARY_DIR}/shell/qml"
    "${CMAKE_SOURCE_DIR}/marathon-silica"
)
# Keel's QML on a development host; devices have keel-silica in Qt's path.
if(DEFINED ENV{KEEL_QML})
    list(APPEND _shell_qml_import_path "$ENV{KEEL_QML}")
endif()
set_property(TARGET marathon-shell PROPERTY QT_QML_IMPORT_PATH ${_shell_qml_import_path})
# The import scan only links static QML plugins; Keel's are shared and load at
# runtime, and scanning them warns that their link targets don't exist.
set_property(TARGET marathon-shell PROPERTY QT_QML_MODULE_NO_IMPORT_SCAN TRUE)

# Link the big resources (sounds-only qrc) to the target
target_sources(marathon-shell PRIVATE ${SHELL_SOUNDS})

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-shell ${QML_FILES})
endif()

find_package(PkgConfig REQUIRED)
# libdrm: direct atomic CRTC ACTIVE toggle for the Doze display-off path
# (WaylandCompositor::setDisplayPowerState). Present via mesa-dev on the
# Alpine build root; the shell already holds the DRM master fd from eglfs.
pkg_check_modules(LIBDRM REQUIRED libdrm)
target_include_directories(marathon-shell PRIVATE
    ${LIBDRM_INCLUDE_DIRS}
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/components
    ${CMAKE_CURRENT_SOURCE_DIR}/src/services
    ${CMAKE_CURRENT_SOURCE_DIR}/src/managers
    ${CMAKE_CURRENT_SOURCE_DIR}/src/models
    ${CMAKE_CURRENT_SOURCE_DIR}/src/controllers
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner/ipc
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
    OUTPUT_NAME marathon-shell-bin
)

install(TARGETS marathon-shell
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

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
# package() step strips this directive post-install.

# Sora and JetBrains Mono for fontconfig users (greetd, terminals, apps
# outside the shell's qrc). The static cuts register as distinct styles.
install(FILES
    qml/theme/fonts/Sora.ttf
    qml/theme/fonts/Sora-Thin.ttf
    qml/theme/fonts/Sora-ExtraLight.ttf
    qml/theme/fonts/Sora-Light.ttf
    qml/theme/fonts/Sora-Regular.ttf
    qml/theme/fonts/Sora-Medium.ttf
    qml/theme/fonts/Sora-SemiBold.ttf
    qml/theme/fonts/Sora-Bold.ttf
    qml/theme/fonts/Sora-ExtraBold.ttf
    qml/theme/fonts/JetBrainsMono-Medium.ttf
    DESTINATION share/fonts/marathon
)

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/dbus/marathon-ngf.conf
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/dbus-1/system.d)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/dbus/marathon.portal
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/xdg-desktop-portal/portals)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/dbus/keel-actions.json
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/keel/actions RENAME org.marathonos.shell.json)
# Default-ambience GTK 3 themes and KDE colour scheme (ToolkitTheme); the
# shell rewrites the GTK files per user as the ambience changes.
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/toolkit-themes/themes/
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/themes)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/toolkit-themes/color-schemes/Marathon.colors
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/color-schemes)
