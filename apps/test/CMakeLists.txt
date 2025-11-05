# Test App - System Service Testing Suite

set(APP_NAME test)

# Collect all QML files
file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# Pure QML app
add_marathon_app(${APP_NAME}
    URI "MarathonApp.Test"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
