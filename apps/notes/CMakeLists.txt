
# Notes App - Note taking application

set(APP_NAME notes)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Notes"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)

install(FILES keel-actions.json DESTINATION share/keel/actions RENAME org.marathonos.notes.json)
