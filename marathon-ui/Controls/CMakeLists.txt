# MarathonUI.Controls module

qt6_add_qml_module(marathon-ui-controls
    URI MarathonUI.Controls
    VERSION 2.0
    QML_FILES
        MSlider.qml
        MToggle.qml
        MCheckbox.qml
        MRadioButton.qml
        MRadioGroup.qml
        MDropdown.qml
        MComboBox.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Controls
)

target_link_libraries(marathon-ui-controls PRIVATE
    marathon-ui-theme
    marathon-ui-core
)

install(TARGETS marathon-ui-controls
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Controls/
    DESTINATION ${MARATHON_UI_DIR}/Controls
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

