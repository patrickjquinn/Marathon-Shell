# Settings App - System configuration interface

set(APP_NAME settings)

file(GLOB_RECURSE QML_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    src/StorageInfo.cpp
    src/StorageInfo.h
    src/KeyboardSettingsStore.cpp
    src/KeyboardSettingsStore.h
    src/SettingsController.cpp
    src/SettingsController.h
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Settings"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
