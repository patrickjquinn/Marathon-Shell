# MarathonUI.Core module

set(CORE_QML_FILES
    MButton.qml
    MIconButton.qml
    MCircularIconButton.qml
    MTextInput.qml
    MTextArea.qml
    MLabel.qml
    MDateTimePicker.qml
    MImageButton.qml
    MEmptyState.qml
    Icon.qml
    MBreakpoints.qml
    MResponsive.qml
    MGrid.qml
    MContainer.qml
    LucideGlyphs.js
    MAppIcon.qml
)

# Mark singleton
set_source_files_properties(MBreakpoints.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt6_add_qml_module(marathon-ui-core
    URI MarathonUI.Core
    VERSION 2.0
    QML_FILES ${CORE_QML_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Core
)

target_link_libraries(marathon-ui-core PRIVATE
    marathon-ui-theme
)

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-core ${CORE_QML_FILES})
endif()

install(TARGETS marathon-ui-core
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Core/
    DESTINATION ${MARATHON_UI_DIR}/Core
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

