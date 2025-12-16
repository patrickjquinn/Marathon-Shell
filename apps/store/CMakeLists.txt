# The add_marathon_app function is already available from parent CMakeLists

set(APP_NAME store)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Store"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
