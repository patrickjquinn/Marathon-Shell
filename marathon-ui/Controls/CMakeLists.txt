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

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-controls
        MSlider.qml
        MToggle.qml
        MCheckbox.qml
        MRadioButton.qml
        MRadioGroup.qml
        MDropdown.qml
        MComboBox.qml
    )
endif()

install(TARGETS marathon-ui-controls
    LIBRARY DESTINATION ${MARATHON_UI_DIR}/Controls
    RUNTIME DESTINATION ${MARATHON_UI_DIR}/Controls
)

install(FILES
    ${CMAKE_BINARY_DIR}/MarathonUI/Controls/qmldir
    ${CMAKE_BINARY_DIR}/MarathonUI/Controls/marathon-ui-controls.qmltypes
    DESTINATION ${MARATHON_UI_DIR}/Controls
)

install(FILES
    MSlider.qml
    MToggle.qml
    MCheckbox.qml
    MRadioButton.qml
    MRadioGroup.qml
    MDropdown.qml
    MComboBox.qml
    DESTINATION ${MARATHON_UI_DIR}/Controls
)
