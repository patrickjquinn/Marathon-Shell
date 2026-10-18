# Calendar App - Events and scheduling

set(APP_NAME calendar)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Calendar"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)

install_keel_actions(${APP_NAME} keel-actions.json)
