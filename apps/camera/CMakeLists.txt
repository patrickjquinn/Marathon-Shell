

set(APP_NAME camera)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")
set_source_files_properties(Settings.qml CameraConfigs.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)


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


find_package(Qt6 REQUIRED COMPONENTS Concurrent)
target_link_libraries(${APP_NAME} PRIVATE Qt6::Multimedia Qt6::Concurrent)

install_keel_actions(${APP_NAME} keel-actions.json)
# The capture, settings and gallery QML is the Jolla Camera's (BSD-3-Clause).
install(FILES LICENSE.BSD-3-Clause DESTINATION "${MARATHON_APPS_DIR}/${APP_NAME}")
