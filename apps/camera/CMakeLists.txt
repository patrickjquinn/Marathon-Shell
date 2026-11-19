

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
    src/CameraSession.cpp
    src/CameraSession.h
    src/Recorder.cpp
    src/Recorder.h
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Camera"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)


find_package(PkgConfig REQUIRED)
pkg_check_modules(TURBOJPEG REQUIRED IMPORTED_TARGET libturbojpeg)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET gstreamer-1.0 gstreamer-app-1.0)
pkg_check_modules(LIBCAMERA REQUIRED IMPORTED_TARGET libcamera)
target_link_libraries(${APP_NAME} PRIVATE PkgConfig::TURBOJPEG PkgConfig::GSTREAMER
    PkgConfig::LIBCAMERA)
# libcamera's headers take std::span.
set_target_properties(${APP_NAME} PROPERTIES CXX_STANDARD 20)

install_keel_actions(${APP_NAME} keel-actions.json)
# The capture, settings and gallery QML is the Jolla Camera's (BSD-3-Clause).
install(FILES LICENSE.BSD-3-Clause DESTINATION "${MARATHON_APPS_DIR}/${APP_NAME}")
