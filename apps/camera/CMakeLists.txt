

set(APP_NAME camera)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)


set(SOURCES
    src/SoftwareVideoOutput.cpp
    src/SoftwareVideoOutput.h
    src/CameraController.cpp
    src/CameraController.h
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Camera"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)


target_link_libraries(${APP_NAME} PRIVATE Qt6::Multimedia)
