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

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-lists MDivider.qml)
endif()

install(TARGETS marathon-ui-lists
    LIBRARY DESTINATION ${MARATHON_UI_DIR}/Lists
    RUNTIME DESTINATION ${MARATHON_UI_DIR}/Lists
)

install(FILES
    ${CMAKE_BINARY_DIR}/MarathonUI/Lists/qmldir
    ${CMAKE_BINARY_DIR}/MarathonUI/Lists/marathon-ui-lists.qmltypes
    DESTINATION ${MARATHON_UI_DIR}/Lists
)

install(FILES MDivider.qml
    DESTINATION ${MARATHON_UI_DIR}/Lists
)
