# MarathonUI.Modals module

qt6_add_qml_module(marathon-ui-modals
    URI MarathonUI.Modals
    VERSION 2.0
    QML_FILES
        MModal.qml
        MConfirmDialog.qml
        MSheet.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Modals
)

target_link_libraries(marathon-ui-modals PRIVATE
    marathon-ui-theme
    marathon-ui-core
)

install(TARGETS marathon-ui-modals
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Modals/
    DESTINATION ${MARATHON_UI_DIR}/Modals
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

