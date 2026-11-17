# Radio: the FM receiver, through marathon-radiod.

set(APP_NAME radio)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Radio"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
