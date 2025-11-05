# MarathonUI.Containers module

qt6_add_qml_module(marathon-ui-containers
    URI MarathonUI.Containers
    VERSION 2.0
    QML_FILES
        MCard.qml
        MPage.qml
        MSection.qml
        MListItem.qml
        MApp.qml
        MLayer.qml
        MScrollView.qml
        MSectionHeader.qml
        MSwipeDelegate.qml
        MPullToRefresh.qml
        MFormCard.qml
        MFormField.qml
        MListTile.qml
        MPanel.qml
        MSettingsListItem.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Containers
)

target_link_libraries(marathon-ui-containers PRIVATE
    marathon-ui-theme
    marathon-ui-core
    marathon-ui-controls
    marathon-ui-effects
)

install(TARGETS marathon-ui-containers
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Containers/
    DESTINATION ${MARATHON_UI_DIR}/Containers
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

