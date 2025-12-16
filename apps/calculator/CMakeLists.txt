# Calculator App

set(APP_NAME calculator)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Calculator"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
