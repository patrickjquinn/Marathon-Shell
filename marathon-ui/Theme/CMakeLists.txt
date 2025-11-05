# MarathonUI.Theme module

set(THEME_QML_FILES
    MColors.qml
    MTypography.qml
    MSpacing.qml
    MRadius.qml
    MElevation.qml
    MMotion.qml
)

# Mark singletons
set_source_files_properties(${THEME_QML_FILES} PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt6_add_qml_module(marathon-ui-theme
    URI MarathonUI.Theme
    VERSION 2.0
    QML_FILES ${THEME_QML_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Theme
)

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-theme ${THEME_QML_FILES})
endif()

install(TARGETS marathon-ui-theme
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Theme/
    DESTINATION ${MARATHON_UI_DIR}/Theme
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

