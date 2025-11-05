# MarathonUI.Feedback module

qt6_add_qml_module(marathon-ui-feedback
    URI MarathonUI.Feedback
    VERSION 2.0
    QML_FILES
        MBadge.qml
        MActivityIndicator.qml
        MProgressBar.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Feedback
)

target_link_libraries(marathon-ui-feedback PRIVATE
    marathon-ui-theme
    marathon-ui-core
)

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-feedback
        MBadge.qml
        MActivityIndicator.qml
        MProgressBar.qml
    )
endif()

install(TARGETS marathon-ui-feedback
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Feedback/
    DESTINATION ${MARATHON_UI_DIR}/Feedback
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

