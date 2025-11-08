# MarathonUI.Effects module

set(EFFECTS_QML_FILES
    MRipple.qml
    MHaptics.qml
)

# Mark singleton
set_source_files_properties(MHaptics.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt6_add_qml_module(marathon-ui-effects
    URI MarathonUI.Effects
    VERSION 2.0
    QML_FILES ${EFFECTS_QML_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Effects
)

target_link_libraries(marathon-ui-effects PRIVATE
    marathon-ui-theme
)

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-effects ${EFFECTS_QML_FILES})
endif()

install(TARGETS marathon-ui-effects
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Effects/
    DESTINATION ${MARATHON_UI_DIR}/Effects
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

