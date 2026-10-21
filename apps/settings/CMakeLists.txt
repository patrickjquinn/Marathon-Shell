# Settings App - System configuration interface

set(APP_NAME settings)

file(GLOB_RECURSE QML_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Settings"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)

install_keel_actions(${APP_NAME} keel-actions.json)
