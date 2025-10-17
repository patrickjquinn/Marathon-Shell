# Settings App - System configuration interface

set(APP_NAME settings)

# Collect all QML files
file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# Pure QML app (Settings primarily uses shell C++ backends)
add_marathon_app(${APP_NAME}
    URI "MarathonApp.Settings"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)

