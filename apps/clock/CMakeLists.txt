# Clock App - Alarms, Timer, Stopwatch, World Clock

set(APP_NAME clock)

# Collect all QML files
file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# Include SVG assets in the QML module's QRC so `Qt.resolvedUrl("../assets/...")` works
# even when the app is loaded from `qrc:/qt/qml/MarathonApp/Clock/...`.
file(GLOB_RECURSE ASSET_FILES RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/*"
)

# C++ sources for native alarm/timer handling (future)
set(SOURCES
    # Future: src/alarmmanager.cpp
    # Future: src/timermanager.cpp
)

# Pure QML for now
add_marathon_app(${APP_NAME}
    URI "MarathonApp.Clock"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
    RESOURCES ${ASSET_FILES}
)
