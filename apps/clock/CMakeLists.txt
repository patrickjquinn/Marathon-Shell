# Clock App - Alarms, Timer, Stopwatch, World Clock

set(APP_NAME clock)

# Collect all QML files
file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# C++ sources for native alarm/timer handling (future)
set(SOURCES
    # Future: src/alarmmanager.cpp
    # Future: src/timermanager.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Clock"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
else()
    # Pure QML for now
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Clock"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()

