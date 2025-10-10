project(marathon-shell)

set(SOURCES
    main.cpp
)

set(QML_FILES
    qml/Main.qml
    qml/MarathonShell.qml
    qml/components/Icon.qml
    qml/components/MarathonToggle.qml
    qml/components/MarathonCard.qml
    qml/components/MarathonListItem.qml
    qml/components/MarathonLockScreen.qml
    qml/components/MarathonPinScreen.qml
    qml/components/MarathonAppGrid.qml
    qml/components/MarathonNavBar.qml
    qml/components/MarathonStatusBar.qml
    qml/components/MarathonBottomBar.qml
    qml/components/MarathonMessagingHub.qml
    qml/components/MarathonQuickSettings.qml
    qml/components/MarathonTaskSwitcher.qml
    qml/components/MarathonPeek.qml
    qml/components/MarathonHub.qml
    qml/components/MarathonAppWindow.qml
    qml/stores/AppStore.qml
    qml/stores/WallpaperStore.qml
    qml/stores/SystemStatusStore.qml
    qml/stores/SystemControlStore.qml
    qml/stores/TaskManagerStore.qml
    qml/stores/NotificationStore.qml
    qml/theme/Theme.qml
    qml/theme/Colors.qml
    qml/theme/Typography.qml
    qml/theme/Layout.qml
)

qt6_add_executable(marathon-shell ${SOURCES})

qt6_add_qml_module(marathon-shell
    URI MarathonOS.Shell
    VERSION 1.0
    QML_FILES ${QML_FILES}
    RESOURCES
        resources.qrc
        qml/theme/qmldir
        qml/stores/qmldir
)

target_link_libraries(marathon-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
)

if(APPLE)
    set_target_properties(marathon-shell PROPERTIES
        MACOSX_BUNDLE FALSE
    )
endif()

