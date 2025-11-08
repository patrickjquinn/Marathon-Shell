# MarathonUI.Navigation module

qt6_add_qml_module(marathon-ui-navigation
    URI MarathonUI.Navigation
    VERSION 2.0
    QML_FILES
        MTopBar.qml
        MBottomBar.qml
        MActionBar.qml
        MNavigationPane.qml
        MTabBar.qml
        MSwipeView.qml
        MPageIndicator.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Navigation
)

target_link_libraries(marathon-ui-navigation PRIVATE
    marathon-ui-theme
    marathon-ui-core
)

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-navigation
        MTopBar.qml
        MBottomBar.qml
        MActionBar.qml
        MNavigationPane.qml
        MTabBar.qml
        MSwipeView.qml
        MPageIndicator.qml
    )
endif()

install(TARGETS marathon-ui-navigation
    LIBRARY DESTINATION ${MARATHON_UI_DIR}
    RUNTIME DESTINATION ${MARATHON_UI_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Navigation/
    DESTINATION ${MARATHON_UI_DIR}/Navigation
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

