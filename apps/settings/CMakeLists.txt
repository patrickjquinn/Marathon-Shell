# Settings App - System configuration interface

set(APP_NAME settings)

file(GLOB_RECURSE QML_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

set(SOURCES
    src/AndroidApps.cpp
    src/AndroidApps.h
    src/MmsSettings.cpp
    src/MmsSettings.h
    src/StorageInfo.cpp
    src/StorageInfo.h
    src/TimeZoneList.cpp
    src/TimeZoneList.h
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

find_package(Qt6 REQUIRED COMPONENTS DBus)
target_link_libraries(${APP_NAME} PRIVATE Qt6::DBus)

install_keel_actions(${APP_NAME} keel-actions.json)
