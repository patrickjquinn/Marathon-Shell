set(SOURCES
    main.cpp
)

set(QML_FILES
    qml/Main.qml
    qml/MarathonShell.qml
    qml/MarathonUI/Theme/qmldir
    qml/MarathonUI/Theme/MColors.qml
    qml/MarathonUI/Theme/MTypography.qml
    qml/MarathonUI/Theme/MSpacing.qml
    qml/MarathonUI/Theme/MRadius.qml
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
    qml/MarathonUI/Lists/qmldir
    qml/MarathonUI/Lists/MListItem.qml
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
    qml/components/UniversalSearch.qml
    qml/components/ScreenshotPreview.qml
    qml/components/BackGestureIndicator.qml
    qml/components/ShareSheet.qml
    qml/components/AppContextMenu.qml
    qml/components/ClipboardManager.qml
    qml/components/ConnectionToast.qml
    qml/components/VirtualKeyboard.qml
    qml/components/QuickSettingsTile.qml
    qml/components/MediaPlaybackManager.qml
    qml/apps/settings/qmldir
    qml/apps/settings/SettingsApp.qml
    qml/apps/template/TemplateApp.qml
    qml/apps/settings/pages/AboutPageNew.qml
    qml/apps/settings/pages/WiFiPageRefactored.qml
    qml/apps/settings/pages/SettingsMainPage.qml
    qml/apps/settings/pages/WiFiPage.qml
    qml/apps/settings/pages/BluetoothPage.qml
    qml/apps/settings/pages/CellularPage.qml
    qml/apps/settings/pages/DisplayPage.qml
    qml/apps/settings/pages/SoundPage.qml
    qml/apps/settings/pages/NotificationsPage.qml
    qml/apps/settings/pages/StoragePage.qml
    qml/apps/settings/pages/AboutPage.qml
    qml/apps/settings/components/SettingsPageTemplate.qml
    qml/stores/AppStore.qml
    qml/stores/WallpaperStore.qml
    qml/stores/SystemStatusStore.qml
    qml/stores/SystemControlStore.qml
    qml/stores/TaskManagerStore.qml
    qml/stores/NotificationStore.qml
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
    qml/services/SettingsManager.qml
    qml/services/ScreenshotService.qml
    qml/services/HapticService.qml
    qml/services/ClipboardService.qml
    qml/services/NavigationRouter.qml
)

qt6_add_executable(marathon-shell ${SOURCES})

# Mark singleton files BEFORE adding QML module
set(SINGLETON_FILES
    qml/MarathonUI/Theme/MColors.qml
    qml/MarathonUI/Theme/MTypography.qml
    qml/MarathonUI/Theme/MSpacing.qml
    qml/MarathonUI/Theme/MRadius.qml
    qml/stores/AppStore.qml
    qml/stores/WallpaperStore.qml
    qml/stores/SystemStatusStore.qml
    qml/stores/SystemControlStore.qml
    qml/stores/TaskManagerStore.qml
    qml/stores/NotificationStore.qml
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
    qml/services/SettingsManager.qml
    qml/services/ScreenshotService.qml
    qml/services/HapticService.qml
    qml/services/ClipboardService.qml
    qml/services/NavigationRouter.qml
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
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Core
)

target_link_libraries(marathon-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::DBus
)

if(TARGET Qt6::VirtualKeyboard)
    target_link_libraries(marathon-shell PRIVATE Qt6::VirtualKeyboard)
    target_compile_definitions(marathon-shell PRIVATE HAVE_VIRTUALKEYBOARD)
endif()

set_target_properties(marathon-shell PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

install(TARGETS marathon-shell
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
