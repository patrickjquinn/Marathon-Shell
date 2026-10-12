# Phone App - Dialer, Contacts, Call History

set(APP_NAME phone)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Phone"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
