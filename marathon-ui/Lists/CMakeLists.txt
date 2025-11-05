# MarathonUI.Lists module

qt6_add_qml_module(marathon-ui-lists
    URI MarathonUI.Lists
    VERSION 2.0
    QML_FILES
        MDivider.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Lists
)

target_link_libraries(marathon-ui-lists PRIVATE
    marathon-ui-theme
)

install(TARGETS marathon-ui-lists
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Lists/
    DESTINATION ${MARATHON_UI_DIR}/Lists
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

