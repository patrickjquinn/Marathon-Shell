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
    src/notificationservice.h
    src/notificationservice.cpp
    src/settingsmanager.h
    src/settingsmanager.cpp
    src/bluetoothmanager.h
    src/bluetoothmanager.cpp
    src/marathonappregistry.h
    src/marathonappregistry.cpp
    src/marathonappscanner.h
    src/marathonappscanner.cpp
    src/marathonapploader.h
    src/marathonapploader.cpp
    src/marathonappinstaller.h
    src/marathonappinstaller.cpp
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
    qml/MarathonUI/Theme/qmldir
    qml/MarathonUI/Theme/MColors.qml
    qml/MarathonUI/Theme/MTypography.qml
    qml/MarathonUI/Theme/MSpacing.qml
    qml/MarathonUI/Theme/MRadius.qml
    qml/MarathonUI/Theme/MElevation.qml
    qml/MarathonUI/Theme/MMotion.qml
    qml/MarathonUI/Core/qmldir
    qml/MarathonUI/Core/MButton.qml
    qml/MarathonUI/Core/MIconButton.qml
    qml/MarathonUI/Core/MTextInput.qml
    qml/MarathonUI/Controls/qmldir
    qml/MarathonUI/Controls/MToggle.qml
    qml/MarathonUI/Controls/MSlider.qml
    qml/MarathonUI/Containers/qmldir
    qml/MarathonUI/Containers/MCard.qml
    qml/MarathonUI/Containers/MPage.qml
    qml/MarathonUI/Containers/MSection.qml
    qml/MarathonUI/Containers/MLayer.qml
    qml/MarathonUI/Lists/qmldir
    qml/MarathonUI/Lists/MSectionHeader.qml
    qml/MarathonUI/Lists/MDivider.qml
    qml/MarathonUI/Feedback/qmldir
    qml/MarathonUI/Feedback/MBadge.qml
    qml/MarathonUI/Navigation/qmldir
    qml/MarathonUI/Navigation/MTopBar.qml
    qml/MarathonUI/Navigation/MBottomBar.qml
    qml/components/Icon.qml
    qml/components/MarathonLockScreen.qml
    qml/components/MarathonAppGrid.qml
    qml/components/MarathonNavBar.qml
    qml/components/MarathonStatusBar.qml
    qml/components/MarathonBottomBar.qml
    qml/components/MarathonMessagingHub.qml
    qml/components/MarathonQuickSettings.qml
    qml/components/MarathonTaskSwitcher.qml
    qml/components/MarathonPeek.qml
    qml/components/MarathonToggle.qml
    qml/components/MarathonCard.qml
    qml/components/MarathonListItem.qml
    qml/components/MarathonHub.qml
    qml/components/MarathonPinScreen.qml
    qml/components/MarathonAppWindow.qml
    qml/components/MarathonPageView.qml
    qml/components/MarathonSearch.qml
    qml/components/ui/Button.qml
    qml/components/ui/Input.qml
    qml/components/ui/SettingsListItem.qml
    qml/components/ui/PageIndicator.qml
    qml/components/ui/Modal.qml
    qml/components/ui/TextInputModal.qml
    qml/components/ui/ListPickerModal.qml
    qml/components/ui/StorageDetailsModal.qml
    qml/components/ui/ConfirmDialog.qml
    qml/components/layout/Section.qml
    qml/components/navigation/InertiaNavBar.qml
    qml/components/NotificationToast.qml
    qml/components/SystemHUD.qml
    qml/components/ScreenshotPreview.qml
    qml/components/BackGestureIndicator.qml
    qml/components/ShareSheet.qml
    qml/components/AppContextMenu.qml
    qml/components/ClipboardManager.qml
    qml/components/ConnectionToast.qml
    qml/components/VirtualKeyboard.qml
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
    qml/theme/Colors.qml
    qml/theme/Typography.qml
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
)

qt6_add_executable(marathon-shell ${SOURCES})

# Mark singleton files BEFORE adding QML module
set(SINGLETON_FILES
    qml/MarathonUI/Theme/MColors.qml
    qml/MarathonUI/Theme/MTypography.qml
    qml/MarathonUI/Theme/MSpacing.qml
    qml/MarathonUI/Theme/MRadius.qml
    qml/MarathonUI/Theme/MElevation.qml
    qml/stores/AppStore.qml
    qml/stores/WallpaperStore.qml
    qml/stores/SystemStatusStore.qml
    qml/stores/SystemControlStore.qml
    qml/stores/SessionStore.qml
    qml/stores/UIStore.qml
    qml/core/Constants.qml
    qml/core/Logger.qml
    qml/core/Router.qml
    qml/theme/Colors.qml
    qml/theme/Typography.qml
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
)

foreach(singleton_file ${SINGLETON_FILES})
    set_source_files_properties(${singleton_file} PROPERTIES
        QT_QML_SINGLETON_TYPE TRUE
    )
endforeach()

if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

qt6_add_qml_module(marathon-shell
    URI MarathonOS.Shell
    VERSION 1.0
    QML_FILES ${QML_FILES}
    RESOURCES
        resources.qrc
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell
)

# Add MarathonUI.Theme module
qt6_add_qml_module(marathon-ui-theme
    URI MarathonUI.Theme
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Theme/MColors.qml
        qml/MarathonUI/Theme/MTypography.qml
        qml/MarathonUI/Theme/MSpacing.qml
        qml/MarathonUI/Theme/MRadius.qml
        qml/MarathonUI/Theme/MElevation.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Theme
)

# Add MarathonUI.Containers module
qt6_add_qml_module(marathon-ui-containers
    URI MarathonUI.Containers
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Containers/MCard.qml
        qml/MarathonUI/Containers/MPage.qml
        qml/MarathonUI/Containers/MSection.qml
        qml/MarathonUI/Containers/MListItem.qml
        qml/MarathonUI/Containers/MApp.qml
        qml/MarathonUI/Containers/MLayer.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Containers
)

# Add MarathonUI.Core module
qt6_add_qml_module(marathon-ui-core
    URI MarathonUI.Core
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Core/MButton.qml
        qml/MarathonUI/Core/MIconButton.qml
        qml/MarathonUI/Core/MTextInput.qml
        qml/MarathonUI/Core/MTextArea.qml
        qml/MarathonUI/Core/MLabel.qml
        qml/MarathonUI/Core/MDateTimePicker.qml
        qml/MarathonUI/Core/MDropDown.qml
        qml/MarathonUI/Core/MImageButton.qml
        qml/MarathonUI/Core/MRadioButton.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Core
)

# Add MarathonUI.Controls module
qt6_add_qml_module(marathon-ui-controls
    URI MarathonUI.Controls
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Controls/MSlider.qml
        qml/MarathonUI/Controls/MToggle.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Controls
)

# Add MarathonUI.Lists module
qt6_add_qml_module(marathon-ui-lists
    URI MarathonUI.Lists
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Lists/MSectionHeader.qml
        qml/MarathonUI/Lists/MDivider.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Lists
)

# Add MarathonUI.Navigation module
qt6_add_qml_module(marathon-ui-navigation
    URI MarathonUI.Navigation
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Navigation/MTopBar.qml
        qml/MarathonUI/Navigation/MBottomBar.qml
        qml/MarathonUI/Navigation/MActionBar.qml
        qml/MarathonUI/Navigation/MNavigationPane.qml
        "qml/MarathonUI/Navigation/MTab Control.qml"
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Navigation
)

# Add MarathonUI.Feedback module
qt6_add_qml_module(marathon-ui-feedback
    URI MarathonUI.Feedback
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Feedback/MBadge.qml
        qml/MarathonUI/Feedback/MActivityIndicator.qml
        qml/MarathonUI/Feedback/MProgressBar.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Feedback
)

# Add MarathonUI.Modals module
qt6_add_qml_module(marathon-ui-modals
    URI MarathonUI.Modals
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Modals/MModal.qml
        qml/MarathonUI/Modals/MConfirmDialog.qml
        qml/MarathonUI/Modals/MSheet.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Modals
)

# Add MarathonUI.Effects module
qt6_add_qml_module(marathon-ui-effects
    URI MarathonUI.Effects
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Effects/MInset.qml
        qml/MarathonUI/Effects/MOutset.qml
        qml/MarathonUI/Effects/MRipple.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Effects
)

# Add MarathonUI.Containers MScrollView
qt6_target_qml_sources(marathon-ui-containers
    QML_FILES
        qml/MarathonUI/Containers/MScrollView.qml
)

target_link_libraries(marathon-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::DBus
    Qt6::Multimedia
)

if(TARGET Qt6::VirtualKeyboard)
    target_link_libraries(marathon-shell PRIVATE Qt6::VirtualKeyboard)
    target_compile_definitions(marathon-shell PRIVATE HAVE_VIRTUALKEYBOARD)
endif()

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
