
# Gallery App - Photo and video viewer

set(APP_NAME gallery)

file(GLOB QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
    "${CMAKE_CURRENT_SOURCE_DIR}/pages/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/cover/*.qml"
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Gallery"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
